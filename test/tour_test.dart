import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/data/database.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/domain/preferences.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:prahar/domain/tour.dart';
import 'package:prahar/notifications/notifier.dart';
import 'package:prahar/planner/planner.dart';
import 'package:prahar/state/app_state.dart';
import 'package:prahar/ui/home_screen.dart';
import 'package:prahar/ui/subject_detail_screen.dart';
import 'package:prahar/ui/theme.dart';
import 'package:prahar/ui/tour.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Answers the OS questions without an OS, and counts the permission asks.
/// There is no plugin in a test.
class _QuietNotifier extends Notifier {
  int permissionRequests = 0;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<bool> isBatteryExempt() async => true;

  @override
  Future<bool> requestBatteryExemption() async => true;

  @override
  Future<DateTime> scheduleTest({
    Duration delay = const Duration(minutes: 1),
  }) async => DateTime.now().add(delay);

  @override
  Future<void> syncFromPlan(Plan plan, {DateTime? now}) async {}

  @override
  Future<void> cancelSessionReminders() async {}

  @override
  Future<void> syncDigests(
    List<({DateTime when, String body})> entries,
  ) async {}

  @override
  Future<String> deviceVendor() async => '';

  @override
  Future<bool> hasAutostartScreen() async => false;

  /// Off unless a test says otherwise, as on a fresh install.
  bool notificationsOn = false;

  @override
  Future<bool> notificationsEnabled() async => notificationsOn;
}

/// The first-run tour: which stop it is at, when it runs, and that each stop
/// points at something the student can actually reach on that layout.
///
/// The development phones both have data, so the tour never starts on them by
/// itself. These tests are most of what there is.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final chemistry = Subject(
    id: 's1',
    name: 'Chemistry',
    examDate: DateTime.now().add(const Duration(days: 30)),
  );
  const chapter = Topic(
    id: 't1',
    subjectId: 's1',
    title: 'Chapter 1',
    estimatedMinutes: 120,
  );

  group('which stop', () {
    TourStep? at({
      bool subject = false,
      bool topic = false,
      bool onSubjects = false,
      bool reminders = false,
      bool replay = false,
      Set<TourStep> seen = const {},
    }) => tourStepFor(
      hasSubject: subject,
      hasTopic: topic,
      showingSubjects: onSubjects,
      remindersDone: reminders,
      replay: replay,
      seen: seen,
    );

    const intro = {TourStep.welcome, TourStep.navigation};

    test('an empty app walks from the welcome to adding a subject', () {
      expect(at(), TourStep.welcome);
      expect(at(seen: {TourStep.welcome}), TourStep.navigation);
      expect(at(seen: intro), TourStep.openSubjects);
      expect(at(seen: intro, onSubjects: true), TourStep.addSubject);
    });

    test('coming back with a subject skips the welcome', () {
      expect(at(subject: true), TourStep.openSubjects);
      expect(at(subject: true, onSubjects: true), TourStep.subject);
      expect(
        at(subject: true, onSubjects: true, seen: {TourStep.subject}),
        TourStep.addTopic,
      );
    });

    test('a topic moves on to reminders, then Today, then Plan', () {
      expect(at(subject: true, topic: true), TourStep.reminders);
      expect(at(subject: true, topic: true, reminders: true), TourStep.today);
      expect(
        at(subject: true, topic: true, reminders: true, seen: {TourStep.today}),
        TourStep.plan,
      );
      expect(
        at(
          subject: true,
          topic: true,
          reminders: true,
          seen: {TourStep.today, TourStep.plan},
        ),
        isNull,
      );
    });

    test('a replay shows the welcome again, then skips what is set up', () {
      expect(at(subject: true, topic: true, replay: true), TourStep.welcome);
      expect(
        at(subject: true, topic: true, replay: true, seen: intro),
        TourStep.reminders,
      );
    });

    test('deleting the subject goes back to adding one', () {
      expect(
        at(onSubjects: true, seen: {...intro, TourStep.subject}),
        TourStep.addSubject,
      );
    });
  });

  group('when it runs', () {
    late Directory dir;
    late PraharDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('prahar_tour');
      db = PraharDatabase();
      await db.open(path: dir.path);
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<AppState> launch({bool notificationsOn = false}) async {
      final state = AppState(
        db: db,
        notifier: _QuietNotifier()..notificationsOn = notificationsOn,
      );
      await state.load();
      return state;
    }

    Future<void> setUpSubject(AppState state) async {
      await state.addSubject(name: 'Chemistry', examDate: chemistry.examDate);
      await state.addTopic(
        subjectId: state.subjects.single.id,
        title: 'Chapter 1',
        unit: EffortUnit.pages,
        amount: 12,
        rate: 3,
      );
    }

    int asks(AppState state) =>
        (state.notifier as _QuietNotifier).permissionRequests;

    test('a fresh install starts it', () async {
      final state = await launch();
      expect(state.tourActive, isTrue);
      expect(state.tourStep, TourStep.welcome);
    });

    test('an install that already had subjects never sees it', () async {
      await db.upsertSubject(chemistry);
      final state = await launch();
      expect(state.tourActive, isFalse);
    });

    test('a restart partway through carries on from the data', () async {
      await launch();
      await db.upsertSubject(chemistry);

      final state = await launch();
      expect(state.tourActive, isTrue);
      expect(
        state.tourStep,
        TourStep.openSubjects,
        reason: 'past the welcome, since a subject already exists',
      );
    });

    test('saving the first topic moves on to reminders', () async {
      final state = await launch();
      await setUpSubject(state);

      expect(state.tourActive, isTrue);
      expect(state.tourStep, TourStep.reminders);
    });

    test('a restart after reminders picks up at Today', () async {
      final first = await launch();
      await setUpSubject(first);
      await first.finishTourReminders();

      expect((await launch()).tourStep, TourStep.today);
    });

    test('finishing reminders asks Android once, if nobody had yet', () async {
      final state = await launch();
      await setUpSubject(state);
      await state.requestReminderPermissions();
      await state.finishTourReminders();

      expect(asks(state), 1);
    });

    test('nothing is asked when Android already allows it', () async {
      // After a restore, or on a replay: the prompts would only be noise.
      final state = await launch(notificationsOn: true);
      await setUpSubject(state);
      await state.finishTourReminders();

      expect(asks(state), 0);
    });

    test('skipping ends it for good', () async {
      await (await launch()).skipTour();
      expect((await launch()).tourActive, isFalse);
    });

    test('skipping asks for reminders, since launch held back', () async {
      final state = await launch();
      await state.skipTour();
      expect(asks(state), 1);
    });

    test('passing the last stop ends it for good', () async {
      final state = await launch();
      await setUpSubject(state);
      await state.finishTourReminders();
      await state.tourNext(TourStep.today);
      await state.tourNext(TourStep.plan);

      expect(state.tourActive, isFalse);
      expect((await launch()).tourActive, isFalse);
    });
  });

  group('on screen', () {
    late Directory dir;
    late PraharDatabase db;
    late _QuietNotifier notifier;
    late AppState state;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('prahar_tour_ui');
      db = PraharDatabase();
      await db.open(path: dir.path);
      notifier = _QuietNotifier();
      // A fresh install: nothing has been allowed yet. Set here because
      // nothing reads it from the notifier until the state is loaded.
      state = AppState(db: db, notifier: notifier)
        ..loading = false
        ..prefs = const Prefs()
        ..notificationsAllowed = false
        ..tourActive = true;
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    /// A subject with a topic and a plan, set straight on the state so
    /// nothing is written.
    void withTopic() {
      final availability = Availability(
        minutesByWeekday: {for (var d = 1; d <= 7; d++) d: 240},
      );
      state
        ..subjects = [chemistry]
        ..topics = const [chapter]
        ..availability = availability
        ..plan = const Planner().generate(
          subjects: [chemistry],
          topics: const [chapter],
          availability: availability,
          today: DateTime.now(),
        );
    }

    Widget app() => ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: PraharTheme.of(Brightness.dark),
        builder: (context, child) => TourHost(child: child!),
        home: HomeScreen(key: UniqueKey()),
      ),
    );

    // Targets report in after a frame, the window is measured after another,
    // and the welcome mark takes a second to draw. Today runs a periodic
    // timer, so pumpAndSettle would never return.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await settle(tester);
    }

    /// For a tap that writes: the write needs real time to land.
    Future<void> tapAndWaitFor(
      WidgetTester tester,
      Finder f,
      String setting,
    ) async {
      await tester.runAsync(() async {
        await tester.tap(f);
        for (var i = 0; i < 100; i++) {
          if ((await db.settings())[setting] == '1') break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await settle(tester);
    }

    const phone = Size(411, 914);
    const sideways = Size(891, 411);
    const tablet = Size(1280, 800);
    const small = Size(320, 640);

    final bubble = find.byKey(const ValueKey('spotlight-bubble'));
    final next = find.byKey(const ValueKey('spotlight-next'));
    final skip = find.byKey(const ValueKey('spotlight-skip'));

    Finder target(TourTargetId id) =>
        find.byWidgetPredicate((w) => w is TourTarget && w.id == id);

    Future<void> tapThrough(WidgetTester tester, Finder f) async {
      await tester.tap(f, warnIfMissed: false);
      await settle(tester);
    }

    void expectFits(WidgetTester tester, Size size) {
      expect(tester.takeException(), isNull);
      final card = tester.getRect(bubble);
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.top, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(size.width));
      expect(card.bottom, lessThanOrEqualTo(size.height));
      // A button scrolled out of sight inside the bubble still has a rect on
      // screen, and a tap there lands on the dimmed layer instead.
      if (next.evaluate().isNotEmpty) {
        expect(
          tester.getRect(next).bottom,
          lessThanOrEqualTo(card.bottom),
          reason: 'Next is scrolled out of sight inside the bubble',
        );
      }
    }

    testWidgets('a phone walks from the welcome to adding a subject', (
      tester,
    ) async {
      await pumpAt(tester, phone);
      expect(state.tourStep, TourStep.welcome);
      expect(bubble, findsOneWidget);

      await tapThrough(tester, next);
      expect(state.tourStep, TourStep.navigation);
      expect(
        tester.getRect(bubble).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
        reason: 'the bubble covers the tabs it is describing',
      );

      await tapThrough(tester, next);
      expect(state.tourStep, TourStep.openSubjects);
      expect(next, findsNothing, reason: 'this stop waits for a tap');

      // Any other tab is held back.
      await tapThrough(tester, find.byIcon(Icons.calendar_month_outlined));
      expect(state.tourStep, TourStep.openSubjects);
      expect(find.byType(SegmentedButton<int>), findsNothing);

      await tapThrough(tester, target(TourTargetId.subjectsTab));
      expect(state.tourStep, TourStep.addSubject);
      expect(
        tester
            .getRect(bubble)
            .overlaps(tester.getRect(find.byType(FloatingActionButton))),
        isFalse,
      );

      await tapThrough(tester, find.byType(FloatingActionButton));
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('steps aside for the sheet, and returns if it closes unsaved', (
      tester,
    ) async {
      state
        ..tourNext(TourStep.welcome)
        ..tourNext(TourStep.navigation);
      await pumpAt(tester, phone);
      await tapThrough(tester, target(TourTargetId.subjectsTab));
      await tapThrough(tester, find.byType(FloatingActionButton));

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(bubble, findsNothing, reason: 'the dim layer is over the sheet');

      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await settle(tester);

      expect(find.byType(BottomSheet), findsNothing);
      expect(state.tourStep, TourStep.addSubject);
      expect(bubble, findsOneWidget);
    });

    testWidgets('picks up at a subject, and follows it onto its page', (
      tester,
    ) async {
      state.subjects = [chemistry];
      await pumpAt(tester, phone);
      expect(
        state.tourStep,
        TourStep.openSubjects,
        reason: 'no welcome for someone with a subject already',
      );

      await tapThrough(tester, target(TourTargetId.subjectsTab));
      expect(state.tourStep, TourStep.subject);
      expect(
        tester.getRect(bubble).top,
        greaterThanOrEqualTo(
          tester.getRect(target(TourTargetId.firstSubject)).bottom,
        ),
      );

      await tapThrough(tester, next);
      expect(state.tourStep, TourStep.addTopic);
      expect(target(TourTargetId.addTopic), findsNothing);

      // The row is what opens the page with the button on it.
      await tapThrough(tester, target(TourTargetId.firstSubject));
      final add = target(TourTargetId.addTopic);
      expect(add, findsOneWidget);
      expect(bubble, findsOneWidget);
      expect(tester.getRect(bubble).overlaps(tester.getRect(add)), isFalse);

      await tapThrough(tester, add);
      expect(
        find.byType(BottomSheet),
        findsOneWidget,
        reason: 'the window is on the button, so the tap reaches it',
      );
    });

    testWidgets('the reminders card asks, then Today and Plan end the tour', (
      tester,
    ) async {
      withTopic();
      await pumpAt(tester, phone);
      expect(state.tourStep, TourStep.reminders);
      expect(
        find.byKey(const ValueKey('tour-allow-notifications')),
        findsOneWidget,
      );

      await tapAndWaitFor(tester, next, 'tour_reminders');
      expect(
        notifier.permissionRequests,
        1,
        reason: 'Continue asks when the Allow row was never used',
      );
      expect(state.tourStep, TourStep.today);
      final card = target(TourTargetId.today);
      expect(card, findsOneWidget);
      expect(tester.getRect(bubble).overlaps(tester.getRect(card)), isFalse);

      await tapThrough(tester, next);
      expect(state.tourStep, TourStep.plan);
      final plan = target(TourTargetId.planTab);
      expect(plan, findsOneWidget);
      expect(tester.getRect(bubble).overlaps(tester.getRect(plan)), isFalse);

      await tapAndWaitFor(tester, next, 'tour_done');
      expect(state.tourActive, isFalse);
      expect(bubble, findsNothing);
    });

    testWidgets('Continue closes the subject page to show Today', (
      tester,
    ) async {
      withTopic();
      await pumpAt(tester, phone);
      Navigator.of(tester.element(find.byType(HomeScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => SubjectDetailScreen(subjectId: chemistry.id),
        ),
      );
      await settle(tester);
      expect(find.byType(SubjectDetailScreen), findsOneWidget);

      await tapAndWaitFor(tester, next, 'tour_reminders');

      expect(find.byType(SubjectDetailScreen), findsNothing);
      expect(target(TourTargetId.today), findsOneWidget);
    });

    testWidgets('Skip ends the tour, remembers it, and asks for reminders', (
      tester,
    ) async {
      await pumpAt(tester, phone);
      await tapAndWaitFor(tester, skip, 'tour_done');

      expect(bubble, findsNothing);
      expect(state.tourActive, isFalse);
      expect(notifier.permissionRequests, 1);
      final settings = await tester.runAsync(db.settings);
      expect(settings!['tour_done'], '1');
    });

    testWidgets('the help sheet shows the tour again', (tester) async {
      withTopic();
      state.tourActive = false;
      await pumpAt(tester, phone);
      expect(bubble, findsNothing);

      await tapThrough(tester, find.byKey(const ValueKey('today-help')));
      await tapThrough(tester, find.byKey(const ValueKey('help-sheet-tour')));

      expect(find.byType(BottomSheet), findsNothing);
      expect(state.tourStep, TourStep.welcome);
      expect(bubble, findsOneWidget);

      await tapThrough(tester, next);
      await tapThrough(tester, next);
      expect(
        state.tourStep,
        TourStep.reminders,
        reason: 'already set up, so the subject stops are passed',
      );
    });

    testWidgets('sideways, the tabs stop sits beside the rail', (tester) async {
      state.tourNext(TourStep.welcome);
      await pumpAt(tester, sideways);
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        tester.getRect(bubble).left,
        greaterThanOrEqualTo(tester.getRect(find.byType(NavigationRail)).right),
      );

      await tapThrough(tester, next);
      await tapThrough(tester, target(TourTargetId.subjectsTab));
      expect(state.tourStep, TourStep.addSubject);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tablet points straight at the topic button in the pane', (
      tester,
    ) async {
      state
        ..subjects = [chemistry]
        ..tourNext(TourStep.subject);
      await pumpAt(tester, tablet);

      await tapThrough(tester, target(TourTargetId.subjectsTab));
      expect(state.tourStep, TourStep.addTopic);

      final add = target(TourTargetId.addTopic);
      expect(add, findsOneWidget);
      expect(tester.getRect(bubble).overlaps(tester.getRect(add)), isFalse);

      await tapThrough(tester, add);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('fits a small phone at a large font', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpAt(tester, small);

      expectFits(tester, small);
      await tapThrough(tester, next);
      expectFits(tester, small);
      await tapThrough(tester, next);
      expectFits(tester, small);
      await tapThrough(tester, target(TourTargetId.subjectsTab));
      expect(state.tourStep, TourStep.addSubject);
      expectFits(tester, small);
    });

    testWidgets('the reminders card fits a small phone at a large font', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      withTopic();
      await pumpAt(tester, small);

      expect(state.tourStep, TourStep.reminders);
      expectFits(tester, small);
    });
  });
}
