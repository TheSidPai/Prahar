import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/data/database.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/domain/preferences.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:prahar/notifications/notifier.dart';
import 'package:prahar/planner/calibration.dart';
import 'package:prahar/planner/planner.dart';
import 'package:prahar/state/app_state.dart';
import 'package:prahar/ui/plan_screen.dart';
import 'package:prahar/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Progress must not read the database while it is drawing.
///
/// The calibration card used to hand a FutureBuilder
/// `state.calibrationSuggestions()` straight from `build`. Three consequences,
/// only one of which was visible:
///
///  - a database query on every rebuild, and every notifyListeners rebuilds
///    Progress, so one per edit, per tap, and per minute tick;
///  - a fresh future each time, so the card blinked out and back whenever
///    something unrelated changed;
///  - in a widget test, a query that fake-async never completes, which fails
///    whichever test the binding checks next with a pending-timer error whose
///    stack names sqflite and Progress rather than anything the test did.
///
/// The third is what makes this worth a test file: the symptom appeared
/// somewhere else entirely, so nothing pointed at Progress.
///
/// Note what these tests assert and what they do not. Asserting "no pending
/// timer" was tried first and was useless: it passed against the broken code,
/// because in isolation the query happens to finish. What does catch it is
/// seeding `state.calibration` and writing nothing to the database, so the
/// card can only appear if Progress read the state. Both tests were confirmed
/// to fail against the FutureBuilder version before being kept.
void main() {
  late Directory dir;
  late PraharDatabase db;
  late AppState state;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_progress_query');
    db = PraharDatabase();
    await db.open(path: dir.path);

    state = AppState(db: db, notifier: Notifier())
      ..loading = false
      ..prefs = const Prefs()
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
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: PraharTheme.of(Brightness.dark),
      home: const ProgressScreen(),
    ),
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pump();
  }

  const suggestion = CalibrationSuggestion(
    subjectId: 's1',
    unit: EffortUnit.pages,
    currentRate: 3,
    recommendedRate: 4.5,
    sampleCount: 4,
    affectedTopicIds: ['t1'],
  );

  testWidgets('the card is drawn from state, not from a query', (tester) async {
    // The load-bearing test. Nothing is written to the database, so the only
    // way this card can appear is if Progress read state.calibration. A
    // FutureBuilder over a query would find no completed topics and draw
    // nothing, which is exactly how the old version fails here.
    state.calibration = const [suggestion];

    await pump(tester);

    expect(find.text('Your actual pace'), findsOneWidget);
  });

  testWidgets('it appears on the first frame, without settling', (
    tester,
  ) async {
    // A query in build cannot resolve within one pump, so the old version
    // drew nothing on the first frame and blinked the card in afterwards.
    // Rebuilding handed it a new future each time and blinked it out again.
    state.calibration = const [suggestion];

    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());

    expect(find.text('Your actual pace'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      state.notifyListeners();
      await tester.pump();
      expect(
        find.text('Your actual pace'),
        findsOneWidget,
        reason: 'the card must not blink out on an unrelated rebuild',
      );
    }
  });

  test('calibration is a plain list, not a future', () {
    // Typing it as a Future here would put the query back where it was.
    expect(state.calibration, isA<List<CalibrationSuggestion>>());
    expect(state.calibration, isEmpty);
  });
}
