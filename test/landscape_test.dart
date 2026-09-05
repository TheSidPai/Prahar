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
import 'package:prahar/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Does the sideways layout actually lay out?
///
/// These exist because the device cannot answer the question: MIUI refuses adb
/// input injection, so nothing here can rotate the phone or drive it to a
/// screen. A build succeeding proves only that the code compiles — overflow is
/// a *runtime* failure, and the two-pane layouts were written blind.
///
/// So the app is pumped at real device sizes and asked whether it threw. The
/// case that matters most is the one this layout exists for: a phone in
/// landscape is 411dp tall, and five labelled rail destinations want about
/// 360 of it once the app bar has taken its share.
///
/// One thing to know when reading a failure: the test font draws every glyph
/// as a fixed-width box, so text here is *wider* than on the device. That
/// makes these tests conservative rather than wrong — a row that overflows
/// only in the test is a row that will overflow on a phone set to a large
/// font scale, which is a real condition and worth fixing either way. Three
/// genuine bugs came out of this file on the first run, one of them in the
/// portrait layout that had already shipped.
void main() {
  late Directory dir;
  late PraharDatabase db;
  late AppState state;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_landscape');
    db = PraharDatabase();
    await db.open(path: dir.path);

    // Built by hand rather than through load(), which would reach for the
    // notification plugin and the battery channel — neither of which exists
    // in a test binding. Every field the screens read is public.
    state = AppState(db: db, notifier: Notifier())
      ..loading = false
      ..prefs = const Prefs()
      ..subjects = [
        Subject(
          id: 's1',
          name: 'Data Structures and Algorithms',
          examDate: DateTime.now().add(const Duration(days: 20)),
          colorValue: 0xFFE07A3E,
        ),
        Subject(
          id: 's2',
          name: 'Biology',
          examDate: DateTime.now().add(const Duration(days: 4)),
          colorValue: 0xFF4F46E5,
        ),
      ]
      ..topics = [
        const Topic(
          id: 't1',
          subjectId: 's1',
          title: 'Balanced trees',
          estimatedMinutes: 300,
        ),
        const Topic(
          id: 't2',
          subjectId: 's2',
          title: 'Gene Replication',
          estimatedMinutes: 240,
        ),
      ];

    state.plan = const Planner().generate(
      subjects: state.subjects,
      topics: state.topics,
      availability: Availability(
        minutesByWeekday: {for (var d = 1; d <= 7; d++) d: 300},
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
      home: const HomeScreen(),
    ),
  );

  /// Pumps at a physical size and returns whatever the frame threw — an
  /// overflow reports itself as an exception during layout.
  Future<Object?> pumpAt(WidgetTester tester, Size size, {int tab = 0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pump();

    if (tab != 0) {
      // Move by tapping the destination's icon, so the test exercises the same
      // path a finger does. The icon rather than the label because a label in
      // the rail is not always the hit target, and a tap that quietly misses
      // would leave these tests checking the Today screen five times over
      // while claiming to check five different ones.
      const icons = [
        Icons.today_outlined,
        Icons.calendar_month_outlined,
        Icons.insights_outlined,
        Icons.library_books_outlined,
        Icons.settings_outlined,
      ];
      await tester.tap(find.byIcon(icons[tab]).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // And prove it landed: the app bar titles the current tab, so this fails
      // loudly if the tap missed rather than silently testing nothing.
      final label = const [
        'Today',
        'Plan',
        'Progress',
        'Subjects',
        'Settings',
      ][tab];
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text(label)),
        findsOneWidget,
        reason: 'the tap did not switch to $label',
      );
    }

    final thrown = tester.takeException();
    // Dispose the tree so the screen's one-minute ticker does not outlive the
    // test and fail it for a pending timer.
    await tester.pumpWidget(const SizedBox.shrink());
    return thrown;
  }

  const phoneLandscape = Size(891, 411);
  const phonePortrait = Size(411, 891);
  const tablet = Size(1194, 834);

  group('a phone in landscape', () {
    testWidgets('Today lays out with no overflow', (tester) async {
      expect(await pumpAt(tester, phoneLandscape), isNull);
    });

    testWidgets('navigation is a rail, not a bottom bar', (tester) async {
      tester.view.physicalSize = phoneLandscape;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the rail survives a 411dp-tall screen', (tester) async {
      // The specific failure this guards: five labelled destinations are
      // taller than the body of a landscape phone, so the rail has to scroll
      // rather than overflow.
      tester.view.physicalSize = phoneLandscape;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(tester.takeException(), isNull);
      for (final label in [
        'Today',
        'Plan',
        'Progress',
        'Subjects',
        'Settings',
      ]) {
        expect(find.text(label), findsWidgets, reason: '$label lost from rail');
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final (i, name) in [
      (1, 'Plan'),
      (2, 'Progress'),
      (3, 'Subjects'),
      (4, 'Settings'),
    ]) {
      testWidgets('$name lays out with no overflow', (tester) async {
        expect(await pumpAt(tester, phoneLandscape, tab: i), isNull);
      });
    }
  });

  group('the shapes that already worked still do', () {
    testWidgets('a phone upright keeps the bottom bar', (tester) async {
      tester.view.physicalSize = phonePortrait;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a phone upright lays out with no overflow', (tester) async {
      expect(await pumpAt(tester, phonePortrait), isNull);
    });

    testWidgets('a tablet is two columns but keeps the bottom bar', (
      tester,
    ) async {
      tester.view.physicalSize = tablet;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(
        find.byType(NavigationBar),
        findsOneWidget,
        reason: 'tall enough that a bottom bar is still the easier reach',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
