import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/data/database.dart';
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

/// Records what AppState asks of the OS instead of asking it.
///
/// There is no notification plugin in a test, so the only way to know whether
/// "off" really means off is to watch the calls. The failure this guards
/// against is quiet: a second path that schedules alarms without checking the
/// switch, so reminders come back after the next edit or resume.
class _RecordingNotifier extends Notifier {
  int syncs = 0;
  int cancels = 0;
  int digestSyncs = 0;
  int lastDigestCount = -1;

  void reset() {
    syncs = 0;
    cancels = 0;
    digestSyncs = 0;
    lastDigestCount = -1;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<bool> isBatteryExempt() async => true;

  @override
  Future<void> syncFromPlan(Plan plan, {DateTime? now}) async {
    syncs++;
  }

  @override
  Future<void> cancelSessionReminders() async {
    cancels++;
  }

  @override
  Future<void> syncDigests(List<({DateTime when, String body})> entries) async {
    digestSyncs++;
    lastDigestCount = entries.length;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final subject = Subject(
    id: 's1',
    name: 'Operating Systems',
    examDate: DateTime.now().add(const Duration(days: 15)),
    colorValue: 0xFF4F46E5,
  );
  const topic = Topic(
    id: 't1',
    subjectId: 's1',
    title: 'Virtualization',
    estimatedMinutes: 600,
  );
  final availability = Availability(
    minutesByWeekday: {for (var d = 1; d <= 7; d++) d: 240},
  );

  group('what the switch does to alarms', () {
    late Directory dir;
    late PraharDatabase db;
    late _RecordingNotifier notifier;
    late AppState state;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('prahar_reminders');
      db = PraharDatabase();
      await db.open(path: dir.path);
      notifier = _RecordingNotifier();

      state = AppState(db: db, notifier: notifier)
        ..loading = false
        ..prefs = const Prefs()
        ..subjects = [subject]
        ..topics = const [topic]
        ..availability = availability;
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('switching off takes back the block alarms and sets none', () async {
      await state.updatePrefs(state.prefs.copyWith(remindersEnabled: false));

      expect(notifier.syncs, 0, reason: 'alarms were scheduled while off');
      expect(notifier.cancels, greaterThan(0));
    });

    test('with reminders on, a replan schedules them', () async {
      await state.updatePrefs(state.prefs.copyWith(remindersEnabled: true));

      expect(notifier.syncs, 1);
      expect(notifier.cancels, 0);
    });

    test('a later edit does not quietly turn them back on', () async {
      await state.updatePrefs(state.prefs.copyWith(remindersEnabled: false));
      notifier.reset();

      // Any other change replans. This is the path a second, unguarded call
      // to syncFromPlan would take.
      await state.updatePrefs(state.prefs.copyWith(breakMinutes: 5));

      expect(notifier.syncs, 0);
    });

    test('coming back to the app does not turn them back on', () async {
      await state.updatePrefs(state.prefs.copyWith(remindersEnabled: false));
      notifier.reset();

      await state.refreshAlarms();

      expect(notifier.syncs, 0);
    });

    test('the evening summary is not this switch\'s to silence', () async {
      await state.updatePrefs(state.prefs.copyWith(remindersEnabled: false));

      expect(notifier.digestSyncs, greaterThan(0));
      expect(notifier.lastDigestCount, Notifier.digestDays);
    });

    test('turning them back on brings them back', () async {
      await state.updatePrefs(state.prefs.copyWith(remindersEnabled: false));
      notifier.reset();

      await state.updatePrefs(state.prefs.copyWith(remindersEnabled: true));

      expect(notifier.syncs, 1);
    });

    test('the choice survives a restart', () async {
      await state.updatePrefs(state.prefs.copyWith(remindersEnabled: false));

      final reread = Prefs.fromMap(await db.settings());
      expect(reread.remindersEnabled, isFalse);
    });
  });

  group('on screen', () {
    late Directory dir;
    late PraharDatabase db;
    late AppState state;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('prahar_reminders_ui');
      db = PraharDatabase();
      await db.open(path: dir.path);

      // Prefs are set directly rather than through updatePrefs: that writes to
      // the database, which cannot complete on a widget test's fake time.
      state = AppState(db: db, notifier: _RecordingNotifier())
        ..loading = false
        ..prefs = const Prefs()
        ..subjects = [subject]
        ..topics = const [topic]
        ..availability = availability;

      state.plan = const Planner().generate(
        subjects: state.subjects,
        topics: state.topics,
        availability: availability,
        today: DateTime.now(),
      );
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Widget wrap(Widget home) => ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: PraharTheme.of(Brightness.dark), home: home),
    );

    Future<void> pump(WidgetTester tester, Widget home, {Size? size}) async {
      tester.view.physicalSize = size ?? const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(home));
      await tester.pump();
    }

    testWidgets('Today says so while reminders are off', (tester) async {
      state.prefs = state.prefs.copyWith(remindersEnabled: false);

      await pump(tester, HomeScreen(key: UniqueKey()));

      // The whole reason for the notice: off and forgotten looks exactly like
      // the app being broken.
      expect(find.byType(RemindersOffNotice), findsOneWidget);
      expect(find.text('Turn on'), findsOneWidget);
    });

    testWidgets('and says nothing while they are on', (tester) async {
      await pump(tester, HomeScreen(key: UniqueKey()));

      expect(find.byType(RemindersOffNotice), findsNothing);
    });

    testWidgets('the notice fits a small phone at a large font', (
      tester,
    ) async {
      state.prefs = state.prefs.copyWith(remindersEnabled: false);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(
        tester,
        HomeScreen(key: UniqueKey()),
        size: const Size(320, 640),
      );

      expect(find.byType(RemindersOffNotice), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Settings leads with the switch, showing its state', (
      tester,
    ) async {
      state.prefs = state.prefs.copyWith(remindersEnabled: false);

      await pump(tester, const RemindersPage());

      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Study reminders'),
      );
      expect(tile.value, isFalse);
    });

    testWidgets('Refresh reminders is hidden while there is nothing to set', (
      tester,
    ) async {
      state.prefs = state.prefs.copyWith(remindersEnabled: false);

      await pump(tester, const RemindersPage());

      // With reminders off it would set nothing and report "0 reminders set".
      expect(find.text('Refresh reminders'), findsNothing);
    });

    testWidgets('and back once reminders are on', (tester) async {
      await pump(tester, const RemindersPage());

      expect(find.text('Refresh reminders'), findsOneWidget);
    });
  });
}
