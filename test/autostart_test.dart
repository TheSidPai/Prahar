import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/data/database.dart';
import 'package:prahar/domain/background_limits.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/domain/preferences.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:prahar/notifications/notifier.dart';
import 'package:prahar/planner/planner.dart';
import 'package:prahar/state/app_state.dart';
import 'package:prahar/ui/home_screen.dart';
import 'package:prahar/ui/settings_screen.dart';
import 'package:prahar/ui/theme.dart';
import 'package:prahar/ui/widgets.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The autostart gate, which is the most likely reason a real student would
/// say reminders stopped.
///
/// None of this can be checked on the development phone: it is a Xiaomi, so it
/// exercises exactly one branch of the vendor mapping and none of the "no gate
/// here" cases. It also cannot be checked by looking, because there is no way
/// to make a Xiaomi report itself as a Pixel. So the mapping is pure and
/// tested directly, and the card's visibility rules are tested by driving
/// AppState rather than a device.
void main() {
  group('which phones have a gate', () {
    test('the makers that keep an autostart list are recognised', () {
      for (final m in [
        'xiaomi',
        'redmi',
        'poco',
        'oppo',
        'realme',
        'oneplus',
        'vivo',
        'iqoo',
        'huawei',
        'honor',
        'samsung',
        'tecno',
        'infinix',
        'itel',
      ]) {
        expect(
          BackgroundGate.forManufacturer(m),
          isNotNull,
          reason: '$m gates background starts and would be missed',
        );
      }
    });

    test('a phone without the gate is not warned about one', () {
      // Stock-Android makers. Motorola belongs here with Google: near-stock,
      // no autostart list of its own, so the battery exemption is the whole
      // story exactly as it is on a Pixel.
      for (final m in ['google', 'motorola', 'nothing', 'sony', '']) {
        expect(
          BackgroundGate.resolve(manufacturer: m, hasScreen: false),
          isNull,
          reason: '$m has no autostart list, so the notice is only noise',
        );
      }
    });

    test('nothing resolving means no gate, whatever the badge says', () {
      // The decisive rule. A Xiaomi with no security app installed must not
      // be shown a card promising a screen that is not there.
      expect(
        BackgroundGate.resolve(manufacturer: 'xiaomi', hasScreen: false),
        isNull,
      );
      expect(
        BackgroundGate.resolve(manufacturer: 'oneplus', hasScreen: false),
        isNull,
      );
    });

    test('a screen on an unknown maker still gets a working notice', () {
      // The other half of the rule, and the reason the old manufacturer-only
      // version failed silently: a phone that gates background starts under a
      // brand this app has never heard of used to get nothing at all.
      final gate = BackgroundGate.resolve(
        manufacturer: 'some-new-brand',
        hasScreen: true,
      );
      expect(gate, isNotNull);
      expect(gate!.isGeneric, isTrue);
      expect(
        gate.explanation,
        isNot(contains('some-new-brand')),
        reason: 'generic copy must not name a maker it cannot describe',
      );
    });

    test('a known maker with a screen is named', () {
      final gate = BackgroundGate.resolve(
        manufacturer: 'oneplus',
        hasScreen: true,
      );
      expect(gate!.isGeneric, isFalse);
      expect(gate.vendor, 'OnePlus');
      expect(gate.rowTitle, 'Auto-launch on OnePlus');
    });

    test('the generic gate reads as a sentence, not a fragment', () {
      const g = BackgroundGate.generic;
      expect(g.noticeTitle, 'One more setting on this phone');
      expect(g.rowTitle, 'Background autostart');
      expect(g.explanation, startsWith('This phone'));
    });

    test('an unknown maker is treated as clean, not warned', () {
      expect(BackgroundGate.forManufacturer('some-new-brand'), isNull);
    });

    test('the manufacturer string is matched however it is cased', () {
      // Build.MANUFACTURER is lowercased on the Kotlin side, but nothing in
      // the type system enforces that, and a stray "Xiaomi" reaching here
      // would silently turn the notice off on every Xiaomi.
      expect(BackgroundGate.forManufacturer('Xiaomi')?.vendor, 'Xiaomi');
      expect(BackgroundGate.forManufacturer('  REDMI ')?.vendor, 'Xiaomi');
    });

    test('each brand is named as itself', () {
      // Telling an Infinix owner they are on a Tecno makes the whole notice
      // look like it is guessing, which is the one thing it cannot afford.
      expect(BackgroundGate.forManufacturer('infinix')?.vendor, 'Infinix');
      expect(BackgroundGate.forManufacturer('itel')?.vendor, 'Itel');
      expect(BackgroundGate.forManufacturer('poco')?.vendor, 'Xiaomi');
    });

    test('every gate names the setting it wants turned on', () {
      for (final m in ['xiaomi', 'oppo', 'vivo', 'samsung', 'huawei']) {
        final gate = BackgroundGate.forManufacturer(m)!;
        expect(gate.settingName, isNotEmpty);
        expect(gate.vendor, isNotEmpty);
      }
    });
  });

  group('when the notice is shown', () {
    late Directory dir;
    late PraharDatabase db;
    late AppState state;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('prahar_autostart');
      db = PraharDatabase();
      await db.open(path: dir.path);

      state = AppState(db: db, notifier: Notifier())
        ..loading = false
        ..prefs = const Prefs()
        ..batteryExempt = true
        ..backgroundGate = BackgroundGate.resolve(
          manufacturer: 'xiaomi',
          hasScreen: true,
        );
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('shown on an affected phone that is otherwise set up', () {
      expect(state.showAutostartNotice, isTrue);
    });

    test('not shown on a phone with no such gate', () {
      state.backgroundGate = null;
      expect(state.showAutostartNotice, isFalse);
    });

    test('waits behind the battery warning', () {
      // Two cards competing for the same attention means the more important
      // one loses. The battery warning reports a fault the app has actually
      // checked; this one is advice.
      state.batteryExempt = false;
      expect(state.showAutostartNotice, isFalse);
    });

    test('does not come back once it has been dealt with', () async {
      await state.dismissAutostartNotice();
      expect(state.showAutostartNotice, isFalse);
    });

    test('"Not now" means later, not never', () async {
      await state.snoozeAutostartNotice();
      expect(state.showAutostartNotice, isFalse);
      expect(
        state.prefs.autostartDismissed,
        isFalse,
        reason: 'snoozing is not dismissing; the label promises a later',
      );
      expect(state.prefs.autostartSnoozedUntil, isNotNull);
    });

    test('it comes back on the day it said it would, not the day after', () {
      final t = state.today;

      // Due tomorrow: still away.
      state.prefs = state.prefs.copyWith(
        autostartSnoozedUntil: DateTime(t.year, t.month, t.day + 1),
      );
      expect(state.showAutostartNotice, isFalse);

      // Due today: back. Waiting for the day to pass would quietly turn a
      // one-day snooze into a two-day one.
      state.prefs = state.prefs.copyWith(
        autostartSnoozedUntil: DateTime(t.year, t.month, t.day),
      );
      expect(state.showAutostartNotice, isTrue);
    });

    test('the first wait is a day, which is what the button implies', () async {
      await state.snoozeAutostartNotice();
      expect(
        state.prefs.autostartSnoozedUntil!.difference(state.today).inDays,
        1,
      );
    });

    test('the wait grows, so it cannot ask forever', () async {
      final waits = <int>[];
      for (var i = 0; i < Prefs.autostartSnoozeLadder.length; i++) {
        await state.snoozeAutostartNotice();
        waits.add(
          state.prefs.autostartSnoozedUntil!.difference(state.today).inDays,
        );
      }
      expect(waits, Prefs.autostartSnoozeLadder);
    });

    test('it retires itself once the ladder runs out', () async {
      for (var i = 0; i < Prefs.autostartSnoozeLadder.length; i++) {
        await state.snoozeAutostartNotice();
      }
      expect(state.prefs.autostartDismissed, isFalse);

      // One more "Not now" than there are rungs, and it gives up for good
      // rather than starting the ladder again.
      await state.snoozeAutostartNotice();
      expect(state.prefs.autostartDismissed, isTrue);
      expect(state.showAutostartNotice, isFalse);
    });

    test('a snooze survives a restart', () async {
      await state.snoozeAutostartNotice();

      final reread = Prefs.fromMap(await db.settings());
      expect(reread.autostartSnoozeCount, 1);
      expect(reread.autostartSnoozedUntil, state.prefs.autostartSnoozedUntil);
    });

    test('a corrupt snooze date does not stop the app starting', () {
      final p = Prefs.fromMap(const {'autostart_snoozed_until': 'not a date'});
      expect(p.autostartSnoozedUntil, isNull);
    });

    test('the dismissal survives a restart', () async {
      await state.dismissAutostartNotice();

      final reread = Prefs.fromMap(await db.settings());
      expect(
        reread.autostartDismissed,
        isTrue,
        reason: 'a notice that reappears every launch is nagging',
      );
    });

    test(
      'a preference file that predates the flag still has its one showing',
      () {
        expect(Prefs.fromMap(const {}).autostartDismissed, isFalse);
      },
    );
  });

  group('the card on screen', () {
    late Directory dir;
    late PraharDatabase db;
    late AppState state;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('prahar_autostart_ui');
      db = PraharDatabase();
      await db.open(path: dir.path);

      // A subject is required, not decoration: with an empty database Today
      // renders the first-run screen, which carries no warnings at all, so an
      // unseeded test would pass this card by without ever drawing it.
      state = AppState(db: db, notifier: Notifier())
        ..loading = false
        ..prefs = const Prefs()
        ..batteryExempt = true
        ..backgroundGate = BackgroundGate.resolve(
          manufacturer: 'xiaomi',
          hasScreen: true,
        )
        ..subjects = [
          Subject(
            id: 's1',
            name: 'Thermodynamics',
            examDate: DateTime.now().add(const Duration(days: 12)),
            colorValue: 0xFF4F46E5,
          ),
        ]
        ..topics = const [
          Topic(
            id: 't1',
            subjectId: 's1',
            title: 'Entropy',
            estimatedMinutes: 240,
          ),
        ];

      state.plan = const Planner().generate(
        subjects: state.subjects,
        topics: state.topics,
        availability: Availability(
          minutesByWeekday: {for (var d = 1; d <= 7; d++) d: 240},
        ),
        today: DateTime.now(),
      );
    });

    tearDown(() async {
      // Dismissing notifies first and writes afterwards, on purpose, so a tap
      // in one of these tests leaves a settings write in flight. Closing the
      // database under it throws database_closed against whichever test is
      // running by then, which is a failure that names the wrong test.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Widget app() => ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: PraharTheme.of(Brightness.dark),
        home: HomeScreen(key: UniqueKey()),
      ),
    );

    testWidgets('names the maker and the setting, not a generic warning', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.byType(AutostartNotice), findsOneWidget);
      expect(find.textContaining('Xiaomi'), findsWidgets);
      expect(find.textContaining('Autostart'), findsWidgets);
    });

    testWidgets('fits a small phone at a large font', (tester) async {
      // The same shape that caught the theme toggle and the nav-bar inset:
      // 320dp wide with the font scaled up. A row of two buttons is exactly
      // what overflows here.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: app(),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('dismissing it takes it off the screen', (tester) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pump();

      // runAsync, because dismissing writes to the database and sqflite
      // schedules a real timer to do it. Inside a widget test's fake-async
      // zone that timer can never fire, so the write stays in flight and the
      // binding fails the test on a pending timer rather than on anything
      // about the card. runAsync gives it real time to finish in.
      await tester.runAsync(() async {
        await tester.tap(find.text('Not now'));

        // Wait for the writes to actually land rather than guessing at a
        // delay. Snoozing writes two settings, and a fixed 50ms was enough
        // for the one write dismissing used to do and is not enough for two,
        // which fails as a pending timer rather than as anything readable.
        for (var i = 0; i < 200; i++) {
          final saved = await db.settings();
          if (saved['autostart_snooze_count'] == '1') break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        // The rebuild has to happen in here too. notifyListeners reaches
        // Progress, whose calibration section starts a database query from
        // inside build(), and that query schedules a timer fake-async never
        // runs. pump, not pumpAndSettle: Today's Timer.periodic means settling
        // never finishes.
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      expect(
        state.prefs.autostartDismissed,
        isFalse,
        reason: '"Not now" must snooze, not retire the notice',
      );

      expect(find.byType(AutostartNotice), findsNothing);
    });
  });

  /// The permanent row, in its own group.
  ///
  /// These pump Settings rather than Today, and they were originally in the
  /// group above. That made "dismissing it takes it off the screen" fail on a
  /// pending timer while passing on its own: Today keeps a Timer.periodic
  /// alive, and running a second screen's tests in between left it pending at
  /// a point the binding checked. Order-dependent failures name the wrong
  /// test, so the two screens get separate fixtures.
  group('the row in Settings', () {
    late Directory dir;
    late PraharDatabase db;
    late AppState state;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('prahar_autostart_row');
      db = PraharDatabase();
      await db.open(path: dir.path);

      state = AppState(db: db, notifier: Notifier())
        ..loading = false
        ..prefs = const Prefs()
        ..batteryExempt = true
        ..backgroundGate = BackgroundGate.resolve(
          manufacturer: 'xiaomi',
          hasScreen: true,
        );
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Widget page() => ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: PraharTheme.of(Brightness.dark),
        home: const RemindersPage(),
      ),
    );

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(page());
      await tester.pump();
    }

    testWidgets('survives the notice being dismissed for good', (tester) async {
      // The whole point of the row: the card is one-time, so once it is gone
      // there is otherwise no way back to the setting, and no way for someone
      // to check whether they ever turned it on.
      //
      // Set directly rather than through dismissAutostartNotice, which writes
      // to the database. sqflite schedules a real timer to do that, and inside
      // a widget test's fake-async zone the await never returns: the run
      // stalls until the suite times out and then blames pumpWidget.
      state.prefs = state.prefs.copyWith(autostartDismissed: true);

      await pump(tester);

      expect(find.text('Autostart on Xiaomi'), findsOneWidget);
    });

    testWidgets('is absent on a phone with no such screen', (tester) async {
      state.backgroundGate = null;

      await pump(tester);

      // Sending a Pixel or Motorola owner to look for Autostart is worse than
      // saying nothing, because the setting does not exist to be found.
      expect(find.textContaining('Autostart'), findsNothing);
    });

    testWidgets('names the setting generically when the maker is unknown', (
      tester,
    ) async {
      state.backgroundGate = BackgroundGate.resolve(
        manufacturer: 'some-new-brand',
        hasScreen: true,
      );

      await pump(tester);

      expect(find.text('Background autostart'), findsOneWidget);
      expect(find.textContaining('some-new-brand'), findsNothing);
    });

    testWidgets('the reminder rows say what they do', (tester) async {
      await pump(tester);

      // "Reschedule all reminders" read as "rearrange my timetable", and
      // "Re-request permissions" is a phrase nobody goes looking for. Match
      // the concept, not the wording, per the rule about pinning copy.
      expect(find.textContaining('Reschedule'), findsNothing);
      expect(find.textContaining('Re-request'), findsNothing);
    });
  });
}
