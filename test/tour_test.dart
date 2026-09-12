import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/data/database.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/domain/preferences.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:prahar/domain/tour.dart';
import 'package:prahar/notifications/notifier.dart';
import 'package:prahar/state/app_state.dart';
import 'package:prahar/ui/home_screen.dart';
import 'package:prahar/ui/spotlight.dart';
import 'package:prahar/ui/theme.dart';
import 'package:prahar/ui/tour.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Answers the OS questions without an OS, and counts the permission asks.
class _QuietNotifier extends Notifier {
  int permissionRequests = 0;
  bool notificationsOn = false;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<bool> notificationsEnabled() async => notificationsOn;

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
}

/// The tours: which stops, when they run, and that each stop points at what
/// is really on screen, with every stop moved on by Next.
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

  /// Two blocks today, the first running now, built by hand so the tests do
  /// not depend on the time of day they run at.
  Plan planWithBlocks() {
    final now = DateTime.now();
    final start = (now.hour * 60 + now.minute - 5).clamp(0, 1300);
    StudySession block(String id, int at) => StudySession(
      id: id,
      topicId: 't1',
      subjectId: 's1',
      topicTitle: 'Chapter 1',
      subjectName: 'Chemistry',
      date: DateTime(now.year, now.month, now.day),
      startMinuteOfDay: at,
      durationMinutes: 50,
    );
    return Plan(
      sessions: [block('b1', start), block('b2', start + 55)],
      feasibility: const Feasibility(
        requiredMinutes: 100,
        availableMinutes: 240,
        unscheduledMinutes: 0,
      ),
      generatedAt: now,
    );
  }

  group('which stops', () {
    test('a fresh install walks the eight stops, ending on the button', () {
      expect(mainTourStops(replay: false), [
        TourStop.welcome,
        TourStop.tabs,
        TourStop.subjects,
        TourStop.topics,
        TourStop.today,
        TourStop.planProgress,
        TourStop.reminders,
        TourStop.finish,
      ]);
    });

    test('a replay folds in the first block, and has no button card', () {
      final stops = mainTourStops(
        replay: true,
        hasBlock: true,
        hasLaterBlocks: true,
      );
      expect(stops.sublist(4, 9), [
        TourStop.today,
        TourStop.focus,
        TourStop.skip,
        TourStop.done,
        TourStop.laterBlocks,
      ]);
      expect(stops, isNot(contains(TourStop.finish)));
      expect(
        mainTourStops(replay: true),
        isNot(contains(TourStop.focus)),
        reason: 'nothing to point at without a block',
      );
    });

    test('the first block shows later blocks only when there are some', () {
      expect(firstBlockStops(hasLaterBlocks: true).last, TourStop.laterBlocks);
      expect(
        firstBlockStops(hasLaterBlocks: false),
        isNot(contains(TourStop.laterBlocks)),
      );
    });

    test('subjects and topics are the stops on the Subjects tab', () {
      expect(
        TourStop.values.where((s) => s.onSubjectsTab),
        unorderedEquals([TourStop.subjects, TourStop.topics]),
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

    int asks(AppState state) =>
        (state.notifier as _QuietNotifier).permissionRequests;

    test('a fresh install starts it on the welcome', () async {
      final state = await launch();
      expect(state.tourKind, TourKind.main);
      expect(state.tourStop, TourStop.welcome);
    });

    test('an install that already had subjects never sees it', () async {
      await db.upsertSubject(chemistry);
      expect((await launch()).tourActive, isFalse);
    });

    test('closed partway, it starts over', () async {
      final first = await launch();
      await first.tourNext();
      await db.upsertSubject(chemistry);

      final state = await launch();
      expect(state.tourStop, TourStop.welcome);
    });

    test('Next moves on and Back moves back, never before the first', () async {
      final state = await launch();
      state.tourBack();
      expect(state.tourIndex, 0);
      await state.tourNext();
      await state.tourNext();
      expect(state.tourStop, TourStop.subjects);
      state.tourBack();
      expect(state.tourStop, TourStop.tabs);
    });

    test(
      'Next on reminders asks Android, unless it already allows it',
      () async {
        for (final allowed in [false, true]) {
          final state = await launch(notificationsOn: allowed);
          while (state.tourStop != TourStop.reminders) {
            await state.tourNext();
          }
          await state.tourNext();
          expect(asks(state), allowed ? 0 : 1);
          expect(state.tourStop, TourStop.finish);
          await db.putSetting('tour_done', '');
        }
      },
    );

    test('Skip ends it for good, and asks for reminders', () async {
      final state = await launch();
      await state.skipTour();
      expect(asks(state), 1);
      expect((await launch()).tourActive, isFalse);
    });

    test(
      'Add your first subject ends it for good and asks for the form',
      () async {
        final state = await launch();
        await state.finishTourAddingSubject();
        expect(state.tourActive, isFalse);
        expect(state.addSubjectRequests, 1);
        expect((await launch()).tourActive, isFalse);
      },
    );

    test(
      'the first block tour starts once, when Today shows a block',
      () async {
        final state = await launch();
        state.plan = planWithBlocks();
        state
          ..noteShowingToday(false)
          ..noteShowingToday(true);
        expect(
          state.tourKind,
          TourKind.main,
          reason: 'never over another tour',
        );

        await state.skipTour();
        state
          ..noteShowingToday(false)
          ..noteShowingToday(true);
        expect(state.tourKind, TourKind.firstBlock);
        expect(state.tourStop, TourStop.block);

        while (state.tourActive) {
          await state.tourNext();
        }
        final again = await launch();
        again.plan = planWithBlocks();
        again
          ..noteShowingToday(false)
          ..noteShowingToday(true);
        expect(again.tourActive, isFalse, reason: 'only once');
      },
    );
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
      state = AppState(db: db, notifier: notifier)
        ..loading = false
        ..prefs = const Prefs()
        ..notificationsAllowed = false;
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    void withBlocks() {
      state
        ..subjects = [chemistry]
        ..topics = const [
          Topic(
            id: 't1',
            subjectId: 's1',
            title: 'Chapter 1',
            estimatedMinutes: 120,
          ),
        ]
        ..plan = planWithBlocks();
    }

    Widget app() => ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: PraharTheme.of(Brightness.dark),
        builder: (context, child) => TourHost(child: child!),
        home: HomeScreen(key: UniqueKey()),
      ),
    );

    // Many short frames rather than a few long ones: switching tab, finding
    // the target, sliding the window and drawing the arrow each wait for a
    // frame. Today runs a periodic timer, so pumpAndSettle would never return.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await settle(tester);
    }

    const phone = Size(411, 914);
    const small = Size(320, 640);

    final bubble = find.byKey(const ValueKey('spotlight-bubble'));
    final next = find.byKey(const ValueKey('spotlight-next'));
    final back = find.byKey(const ValueKey('spotlight-back'));
    final skip = find.byKey(const ValueKey('spotlight-skip'));

    Finder target(TourTargetId id) =>
        find.byWidgetPredicate((w) => w is TourTarget && w.id == id);

    List<SpotlightArrow> arrows(WidgetTester tester) =>
        (tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('spotlight-arrows')),
                    )
                    .painter!
                as SpotlightArrowPainter)
            .arrows;

    Future<void> tapNext(WidgetTester tester) async {
      await tester.tap(next);
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

    void expectFits(WidgetTester tester, Size size) {
      expect(tester.takeException(), isNull);
      final card = tester.getRect(bubble);
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.top, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(size.width));
      expect(card.bottom, lessThanOrEqualTo(size.height));
      expect(
        tester.getRect(next).bottom,
        lessThanOrEqualTo(card.bottom),
        reason: 'Next is scrolled out of sight inside the note',
      );
    }

    testWidgets('a phone walks the whole tour, switching tabs itself', (
      tester,
    ) async {
      state.startMainTour();
      await pumpAt(tester, phone);
      expect(state.tourStop, TourStop.welcome);
      expect(back, findsNothing);

      await tapNext(tester);
      expect(state.tourStop, TourStop.tabs);
      expect(
        tester.getRect(bubble).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
      );

      await tapNext(tester);
      expect(state.tourStop, TourStop.subjects);
      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget, reason: 'the tour opened Subjects itself');
      expect(
        arrows(tester).single.end.dx,
        closeTo(tester.getCenter(fab).dx, 1),
      );

      // Nothing under the dim can be tapped.
      await tester.tap(fab, warnIfMissed: false);
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);

      await tapNext(tester);
      expect(state.tourStop, TourStop.topics);
      await tester.tap(back);
      await settle(tester);
      expect(state.tourStop, TourStop.subjects);
      expect(fab, findsOneWidget);

      await tapNext(tester);
      await tapNext(tester);
      expect(state.tourStop, TourStop.today);
      expect(fab, findsNothing, reason: 'back on Today');

      await tapNext(tester);
      expect(state.tourStop, TourStop.planProgress);
      expect(find.byKey(const ValueKey('spotlight-note-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('spotlight-note-1')), findsOneWidget);
      final pair = arrows(tester);
      expect(pair, hasLength(2));
      for (final (i, id) in [
        TourTargetId.planTab,
        TourTargetId.progressTab,
      ].indexed) {
        expect(pair[i].end.dx, closeTo(tester.getCenter(target(id)).dx, 1));
      }

      await tapNext(tester);
      expect(state.tourStop, TourStop.reminders);
      expect(
        find.byKey(const ValueKey('tour-allow-notifications')),
        findsOneWidget,
      );

      await tapNext(tester);
      expect(state.tourStop, TourStop.finish);
      expect(notifier.permissionRequests, 1);

      await tapAndWaitFor(
        tester,
        find.byKey(const ValueKey('tour-add-subject')),
        'tour_done',
      );
      expect(state.tourActive, isFalse);
      expect(bubble, findsNothing);
      expect(
        find.byType(BottomSheet),
        findsOneWidget,
        reason: 'the button opens the subject form',
      );
    });

    testWidgets('Skip ends the tour, remembers it, and asks for reminders', (
      tester,
    ) async {
      state.startMainTour();
      await pumpAt(tester, phone);
      await tapAndWaitFor(tester, skip, 'tour_done');

      expect(bubble, findsNothing);
      expect(state.tourActive, isFalse);
      expect(notifier.permissionRequests, 1);
    });

    testWidgets('the help sheet replays it, with the first block folded in', (
      tester,
    ) async {
      withBlocks();
      await pumpAt(tester, phone);
      expect(bubble, findsNothing);

      await tester.tap(find.byKey(const ValueKey('today-help')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('help-sheet-tour')));
      await settle(tester);

      expect(state.tourStop, TourStop.welcome);
      expect(state.tourLength, 11);
      expect(bubble, findsOneWidget);
    });

    testWidgets('the first block tour points at the real buttons', (
      tester,
    ) async {
      withBlocks();
      state.startFirstBlockTour();
      await pumpAt(tester, phone);
      expect(state.tourStop, TourStop.block);

      for (final (stop, id) in [
        (TourStop.focus, TourTargetId.focus),
        (TourStop.skip, TourTargetId.skipBlock),
        (TourStop.done, TourTargetId.doneBlock),
        (TourStop.laterBlocks, TourTargetId.laterBlocks),
      ]) {
        await tapNext(tester);
        expect(state.tourStop, stop);
        final aim = target(id);
        expect(aim, findsOneWidget);
        expect(tester.getRect(bubble).overlaps(tester.getRect(aim)), isFalse);
        expect(
          arrows(tester).single.end.dx,
          closeTo(tester.getCenter(aim).dx, 1),
        );
      }

      await tapAndWaitFor(tester, next, 'first_block_done');
      expect(state.tourActive, isFalse);
    });

    testWidgets('sideways, the tabs stop sits beside the rail', (tester) async {
      state.startMainTour();
      await pumpAt(tester, const Size(891, 411));
      await tapNext(tester);

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(bubble).left,
        greaterThanOrEqualTo(tester.getRect(find.byType(NavigationRail)).right),
      );
    });

    testWidgets('every stop fits a small phone at a large font', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      state.startMainTour();
      await pumpAt(tester, small);

      while (true) {
        expectFits(tester, small);
        if (state.tourStop == TourStop.finish) break;
        await tapNext(tester);
      }
    });
  });
}
