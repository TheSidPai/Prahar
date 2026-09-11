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
import 'package:prahar/ui/brand.dart';
import 'package:prahar/ui/home_screen.dart';
import 'package:prahar/ui/how_it_works.dart';
import 'package:prahar/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The help button on Today, and the short sheet behind it.
///
/// Prompted by a first-time user who could not tell what to do. The full guide
/// existed and was not found, so what these tests pin is findability: the
/// button is on Today whether or not anything is set up, it can't be mistaken
/// for the logo beside it, and the sheet and the full guide tell the same
/// steps.
void main() {
  late Directory dir;
  late PraharDatabase db;
  late AppState state;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_help');
    db = PraharDatabase();
    await db.open(path: dir.path);

    // Nothing is written to the database in these tests, so none of them meet
    // the fake-time write trap.
    state = AppState(db: db, notifier: Notifier())
      ..loading = false
      ..prefs = const Prefs();
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void withAPlan() {
    final availability = Availability(
      minutesByWeekday: {for (var d = 1; d <= 7; d++) d: 240},
    );
    state
      ..subjects = [
        Subject(
          id: 's1',
          name: 'Operating Systems',
          examDate: DateTime.now().add(const Duration(days: 15)),
          colorValue: 0xFF4F46E5,
        ),
      ]
      ..topics = const [
        Topic(
          id: 't1',
          subjectId: 's1',
          title: 'Virtualization',
          estimatedMinutes: 600,
        ),
      ]
      ..availability = availability;
    state.plan = const Planner().generate(
      subjects: state.subjects,
      topics: state.topics,
      availability: availability,
      today: DateTime.now(),
    );
  }

  Widget wrap(Widget home) => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(theme: PraharTheme.of(Brightness.dark), home: home),
  );

  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(411, 914),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(HomeScreen(key: UniqueKey())));
    await tester.pump();
  }

  final helpButton = find.byKey(const ValueKey('today-help'));
  final fullGuideLink = find.byKey(const ValueKey('help-sheet-full-guide'));

  // pump rather than pumpAndSettle: Today runs a periodic timer, so settling
  // never finishes.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(helpButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Today has a help button once there is a plan', (tester) async {
    withAPlan();
    await pumpHome(tester);

    expect(helpButton, findsOneWidget);
  });

  testWidgets('and on the first-run screen, before anything is set up', (
    tester,
  ) async {
    // The person who most needs help is the one who has added nothing yet.
    await pumpHome(tester);

    expect(helpButton, findsOneWidget);
  });

  testWidgets('it belongs to Today, not to every tab', (tester) async {
    withAPlan();
    await pumpHome(tester);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(helpButton, findsNothing);
  });

  testWidgets('it is kept apart from the logo, which replays when tapped', (
    tester,
  ) async {
    withAPlan();
    await pumpHome(tester);

    final logo = tester.getRect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PraharLogo),
      ),
    );
    final help = tester.getRect(helpButton);

    expect(
      logo.overlaps(help),
      isFalse,
      reason: 'a tap meant for help would replay the mark instead',
    );
  });

  testWidgets('the sheet lists the four steps', (tester) async {
    withAPlan();
    await pumpHome(tester);
    await openSheet(tester);

    for (final step in howPraharWorksSteps) {
      expect(find.text(step.title), findsWidgets);
      expect(find.text(step.short), findsOneWidget);
    }
  });

  testWidgets('the full guide reads the same step titles', (tester) async {
    // Matched through the shared list rather than typed out here, per the
    // rule about pinning copy: if the page stopped reading the list and got
    // its own wording, this is what would notice.
    tester.view.physicalSize = const Size(411, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const HowItWorks(showAppBar: true)));
    await tester.pump();

    for (final step in howPraharWorksSteps) {
      expect(find.text(step.title), findsOneWidget);
    }
  });

  testWidgets('the full guide is one tap further', (tester) async {
    withAPlan();
    await pumpHome(tester);
    await openSheet(tester);

    await tester.tap(fullGuideLink);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byWidgetPredicate((w) => w is HowItWorks && w.showAppBar),
      findsOneWidget,
    );
  });

  testWidgets('the sheet fits a small phone at a large font', (tester) async {
    withAPlan();
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpHome(tester, size: const Size(320, 640));
    await openSheet(tester);

    expect(tester.takeException(), isNull);
    expect(fullGuideLink, findsOneWidget);
  });
}
