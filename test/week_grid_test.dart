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

/// The week grid: seven columns of absolutely-positioned blocks.
///
/// Positioned children inside a Stack are the one layout shape that fails
/// quietly — a block placed off the bottom of its column is simply not drawn,
/// no overflow stripe, no exception. So these tests check that the grid is
/// actually reading the plan and putting something on the right day, not just
/// that it rendered without complaint.
void main() {
  late Directory dir;
  late PraharDatabase db;
  late AppState state;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_week');
    db = PraharDatabase();
    await db.open(path: dir.path);

    state = AppState(db: db, notifier: Notifier())
      ..loading = false
      ..prefs = const Prefs()
      ..subjects = [
        Subject(
          id: 's1',
          name: 'Physics',
          examDate: DateTime.now().add(const Duration(days: 15)),
          colorValue: 0xFF4F46E5,
        ),
      ]
      ..topics = [
        const Topic(
          id: 't1',
          subjectId: 's1',
          title: 'Rotational motion',
          estimatedMinutes: 600,
        ),
      ]
      // A weekly commitment, so the grid has a busy band to draw behind the
      // blocks as well as the blocks themselves.
      ..availability = Availability(
        minutesByWeekday: {for (var d = 1; d <= 7; d++) d: 240},
        busy: const [
          BusySlot(
            id: 'b1',
            label: 'Lecture',
            startMinute: 9 * 60,
            endMinute: 11 * 60,
            weekday: DateTime.monday,
          ),
        ],
      );

    state.plan = const Planner().generate(
      subjects: state.subjects,
      topics: state.topics,
      availability: state.availability,
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
      home: HomeScreen(key: UniqueKey()),
    ),
  );

  /// Opens Plan and switches to the Week segment.
  Future<void> openWeek(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.calendar_month_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Week'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  const phonePortrait = Size(411, 914);

  testWidgets('the toggle offers Week between Days and Month', (tester) async {
    tester.view.physicalSize = phonePortrait;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.calendar_month_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    for (final label in ['Days', 'Week', 'Month']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('lays out upright with no overflow', (tester) async {
    await openWeek(tester, phonePortrait);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the legend clears the navigation bar in the grid', (
    tester,
  ) async {
    // Seen on a tablet: the legend is pinned under the grid rather than
    // scrolling with it, so nothing inset it and it sat behind the bottom
    // bar. The upright layout was fine because its ListView ends with
    // navBottomInset; the grid is a Column and had to ask for it.
    //
    // The inset is supplied here rather than assumed, because this phone uses
    // gesture navigation and reports nothing. Three-button navigation is what
    // makes the gap real, and it is the case nobody here can see.
    const bar = 48.0;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding = const FakeViewPadding(bottom: bar);
    tester.view.padding = const FakeViewPadding(bottom: bar);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pump();

    // No Week tap here: at this width Plan is two panes and draws the grid
    // beside the month calendar, so there is no Days/Week/Month toggle to
    // press. That is also why this bug only ever showed on a tablet.
    await tester.tap(find.byIcon(Icons.calendar_month_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // "Busy" is the legend's own word for the shaded bands, and the one thing
    // the drawing cannot say about itself.
    final legend = find.text('Busy');
    expect(legend, findsOneWidget);

    final screen = tester.getRect(find.byType(MaterialApp));
    expect(
      tester.getRect(legend).bottom,
      lessThanOrEqualTo(screen.bottom - bar),
      reason: 'the legend is underneath the navigation bar',
    );
  });

  testWidgets('draws the study window down the side', (tester) async {
    await openWeek(tester, phonePortrait);

    // The default window opens at 06:00 and the gutter labels whole hours
    // inside it, so these two must be present and midnight must not.
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('03:00'), findsNothing);
  });

  testWidgets('names the subjects, since a track is too thin to', (
    tester,
  ) async {
    await openWeek(tester, phonePortrait);
    expect(find.text('Physics'), findsWidgets);
  });

  testWidgets('says what the grey means', (tester) async {
    await openWeek(tester, phonePortrait);

    // The one thing no drawing of a timetable can explain about itself, and
    // the reason the legend exists at all rather than just the colours.
    expect(find.text('Busy'), findsOneWidget);
  });

  testWidgets('opening a day names its blocks', (tester) async {
    await openWeek(tester, phonePortrait);

    // Today opens by default, so the topic behind today's blocks is on
    // screen without touching anything. This is the failure the first
    // version had: the shape was visible and the content was not.
    expect(find.text('Rotational motion'), findsWidgets);
  });

  testWidgets('another day can be opened', (tester) async {
    await openWeek(tester, phonePortrait);

    // Tomorrow, by name. The first version had no way to ask about any day
    // but today, which is half the point of looking at a week.
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    await tester.tap(find.text(names[tomorrow.weekday - 1]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Rotational motion'), findsWidgets);
  });

  testWidgets('will not walk backwards out of the planned window', (
    tester,
  ) async {
    await openWeek(tester, phonePortrait);

    final back = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_left),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      back.onPressed,
      isNull,
      reason: 'the past is not planned, so there is nothing to walk back to',
    );
  });
}
