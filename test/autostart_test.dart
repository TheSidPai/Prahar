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
      for (final m in ['google', 'motorola', 'nothing', 'sony', '']) {
        expect(
          BackgroundGate.forManufacturer(m),
          isNull,
          reason: '$m has no autostart list, so the notice is only noise',
        );
      }
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
        ..backgroundGate = BackgroundGate.forManufacturer('xiaomi');
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
        ..backgroundGate = BackgroundGate.forManufacturer('xiaomi')
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
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      // pump, not pumpAndSettle: Today keeps a Timer.periodic running to move
      // its "now" marker, so settling never finishes. One frame is enough,
      // because dismissing notifies before it writes.
      await tester.pump();

      expect(find.byType(AutostartNotice), findsNothing);
    });
  });
}
