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
import 'package:prahar/ui/glass.dart';
import 'package:prahar/ui/home_screen.dart';
import 'package:prahar/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Does content actually start *below* the glass app bar?
///
/// This is the failure mode the layout tests cannot see. A glass bar means the
/// body extends behind it, and a screen that forgets to inset its own scroll
/// view does not overflow, does not throw, and does not fail any existing
/// test — it just draws its first line underneath the title, where only a
/// human looking at the device would notice. Five screens now carry that
/// obligation instead of one, so it needs a net.
///
/// The assertion is deliberately geometric rather than a check that some
/// padding value was passed. What matters is where the pixels landed; how a
/// screen chose to get them there is its own business, and two screens here
/// legitimately do it differently — Plan puts the inset on the Days/Month
/// toggle above its lists, everything else puts it on the scroll view.
void main() {
  late Directory dir;
  late PraharDatabase db;
  late AppState state;

  // The toolbarHeight set in PraharTheme. The test view has no status bar
  // inset, so under a glass bar this is the whole of what a screen must clear.
  const barHeight = 60.0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_glass');
    db = PraharDatabase();
    await db.open(path: dir.path);

    // Built by hand rather than through load(), which would reach for the
    // notification plugin and the battery channel — neither exists in a test
    // binding.
    state = AppState(db: db, notifier: Notifier())
      ..loading = false
      ..subjects = [
        Subject(
          id: 's1',
          name: 'Physics',
          examDate: DateTime.now().add(const Duration(days: 12)),
          colorValue: 0xFF4F46E5,
        ),
      ]
      ..topics = [
        const Topic(
          id: 't1',
          subjectId: 's1',
          title: 'Rotational motion',
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

  // A fresh key every pump, which matters because this file pumps twice in one
  // test. Without it the second HomeScreen is handed the first one's State,
  // still on the tab the first measurement selected — and a selected
  // destination draws its filled icon, so the outlined finder below would find
  // nothing. Keying it is better than pumping an empty tree in between: that
  // disposes the tree, and disposal is what makes the binding fail a test for
  // any timer still pending. Progress starts a sqflite query during build with
  // a ten-second timeout on it, so there is reliably one.
  // The theme is built from prefs, as PraharApp builds it. Passing the
  // defaults instead meant the card theme never changed with the setting
  // under test, so two different styles produced identical trees and an
  // assertion about the difference could only ever fail.
  Widget app() => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: PraharTheme.of(
        Brightness.dark,
        material: state.prefs.materialChoice,
        cardStyle: state.prefs.cardStyle,
      ),
      home: HomeScreen(key: UniqueKey()),
    ),
  );

  /// Pumps upright, moves to [tab], and returns the top edge of [target].
  Future<double> topOf(
    WidgetTester tester,
    int tab,
    Finder target,
  ) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pump();

    if (tab != 0) {
      // Same list, same order as the nav destinations. Kept in step with
      // home_screen.dart by the assertion below, which fails loudly if a tap
      // misses rather than quietly measuring the wrong screen.
      const icons = [
        Icons.today_outlined,
        Icons.calendar_month_outlined,
        null, // Progress is a drawn glyph, not an IconData.
        Icons.library_books_outlined,
        Icons.settings_outlined,
      ];
      final destination = icons[tab] == null
          ? find.byType(PraharProgressGlyph)
          : find.byIcon(icons[tab]!);
      await tester.tap(destination.last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final label = const [
        'Today',
        'Plan',
        'Progress',
        'Subjects',
        'Settings',
      ][tab];
      expect(find.text(label), findsWidgets, reason: 'tap missed tab $tab');
    }

    expect(target, findsWidgets);
    final dy = tester.getTopLeft(target.first).dy;

    // Progress starts a sqflite query while it builds — the calibration
    // section's FutureBuilder — and sqflite hangs a ten-second timeout timer
    // off it. The binding disposes the tree when the test ends and fails the
    // test for any timer still pending, so the query has to be allowed to
    // finish, which needs real async time rather than pumped fake time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    return dy;
  }

  // The first thing each screen draws under the bar. Not the prettiest
  // finders, but each one is the actual top element of its screen, which is
  // the thing that would disappear under the title.
  final firstThing = <int, (String, Finder)>{
    // The Days/Month toggle is in the app bar now, so it would report the
    // same position in both materials and prove nothing. The first day
    // heading in the list is what actually has to clear the header.
    1: (
      'Plan',
      find.descendant(
        of: find.byKey(const ValueKey('plan-days')),
        matching: find.text('Today'),
      ),
    ),
    2: ('Progress', find.byType(Card)),
    3: ('Subjects', find.byType(TextField)),
    4: ('Settings', find.text('SCHEDULE')),
  };

  group('the Today hero answers to Settings > Cards', () {
    // It did in matte, being a plain Card, and did not in glass: a
    // GlassSurface with its own corner and fill drew the identical panel for
    // all five styles. Glass is the material, the card style is the edge.

    Future<int> glassPanelsOnToday(WidgetTester tester, CardStyle style) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      state.prefs = Prefs(
        materialChoice: MaterialChoice.glass,
        cardStyle: style,
      );
      await tester.pumpWidget(app());
      await tester.pump();

      final count = tester.widgetList(find.byType(GlassSurface)).length;

      // Let the screen's own async settle before the binding tears the tree
      // down and fails the test for a timer still pending. Same reason as in
      // `topOf` below.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();

      return count;
    }

    testWidgets('the glass hero sits inside a Card, so the style reaches it', (
      tester,
    ) async {
      await glassPanelsOnToday(tester, CardStyle.hairline);

      expect(
        find.ancestor(
          of: find.byType(GlassSurface),
          matching: find.byType(Card),
        ),
        findsWidgets,
        reason: 'the Card is what carries the outline, shadow and corner',
      );
    });

    testWidgets('a hairline hero shows its edge over the glass', (
      tester,
    ) async {
      // A Card paints its outline underneath its child, and the glass fills
      // the whole shape — so the border was drawn and then covered, and the
      // hero looked borderless whatever Settings said. It is painted as a
      // foreground decoration now, which is what this counts.
      int borders() => tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where(
            (d) =>
                d.position == DecorationPosition.foreground &&
                d.decoration is BoxDecoration &&
                (d.decoration as BoxDecoration).border != null,
          )
          .length;

      await glassPanelsOnToday(tester, CardStyle.plain);
      final plain = borders();

      await glassPanelsOnToday(tester, CardStyle.hairline);
      final hairline = borders();

      expect(
        hairline,
        greaterThan(plain),
        reason: 'the hairline style draws no edge on the glass hero',
      );
    });

    testWidgets('Open means no panel, in glass too', (tester) async {
      final hairline = await glassPanelsOnToday(tester, CardStyle.hairline);
      final open = await glassPanelsOnToday(tester, CardStyle.open);

      // "No card at all" has to mean no glass panel either, or Open would be
      // the one style the hero still ignores.
      expect(
        open,
        lessThan(hairline),
        reason: 'the hero keeps its glass panel under Open',
      );
    });
  });

  // Both materials are measured in one test, because the property worth
  // pinning is that they agree.
  //
  // In matte the scaffold stops the body at the bar, so content lands just
  // below it without anyone asking. In glass the body starts at the top of the
  // screen and the inset has to put content in that same place by hand. Two
  // ways of arriving at one position: assert the position, and the pair of
  // failures is unambiguous. Too high means a screen forgot its inset and is
  // drawing under the title; disagreeing with matte by a bar's height means it
  // applied the inset twice, which is just as wrong and much easier to do —
  // Plan has two widgets that could each plausibly own it.
  for (final entry in firstThing.entries) {
    final (name, finder) = entry.value;

    testWidgets('$name starts in the same place in both materials', (
      tester,
    ) async {
      state.prefs = const Prefs();
      final matte = await topOf(tester, entry.key, finder);

      state.prefs = const Prefs(materialChoice: MaterialChoice.glass);
      final glass = await topOf(tester, entry.key, finder);

      expect(
        matte,
        greaterThanOrEqualTo(barHeight),
        reason: 'matte should already clear the bar; the test is wrong if not',
      );
      expect(
        glass,
        greaterThanOrEqualTo(barHeight),
        reason:
            '$name draws its first element at ${glass}dp, underneath a '
            '${barHeight}dp glass bar it is supposed to start below',
      );
      expect(
        glass,
        closeTo(matte, 1.0),
        reason:
            '$name lands ${glass}dp under glass against ${matte}dp matte — a '
            'gap near ${barHeight}dp means the inset was applied twice',
      );
    });
  }
}
