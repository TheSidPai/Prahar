import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/ui/spotlight.dart';
import 'package:prahar/ui/theme.dart';

/// The spotlight on its own, before any tour uses it.
///
/// What is pinned here is what makes a tour feel finished or broken: taps go
/// where the step says and nowhere else, the note never covers the thing it is
/// talking about, the arrow lands on the middle of its target, the window
/// slides between stops but follows a moving target at once, and nothing
/// throws when a target is missing or the font is large.
void main() {
  late GlobalKey target;
  late int targetTaps;
  late int decoyTaps;
  late int nexts;
  late int skips;
  late int backs;

  setUp(() {
    target = GlobalKey();
    targetTaps = 0;
    decoyTaps = 0;
    nexts = 0;
    skips = 0;
    backs = 0;
  });

  Widget harness(
    SpotlightStep step, {
    Alignment where = Alignment.center,
    int index = 0,
    bool withBack = false,
  }) {
    return MaterialApp(
      theme: PraharTheme.of(Brightness.dark),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: where,
                child: FilledButton(
                  key: target,
                  onPressed: () => targetTaps++,
                  child: const Text('Target'),
                ),
              ),
            ),
            Positioned(
              left: 20,
              top: 60,
              child: TextButton(
                key: const ValueKey('decoy'),
                onPressed: () => decoyTaps++,
                child: const Text('Decoy'),
              ),
            ),
            Positioned.fill(
              child: SpotlightOverlay(
                step: step,
                stepIndex: index,
                stepCount: 3,
                onNext: () => nexts++,
                onBack: withBack ? () => backs++ : null,
                onSkip: () => skips++,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Long enough for the fade, a slide, the welcome mark and the whole arrow,
  // nudges included.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 13; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> pumpStep(
    WidgetTester tester,
    SpotlightStep step, {
    Alignment where = Alignment.center,
    Size size = const Size(411, 914),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(step, where: where));
    await settle(tester);
  }

  final bubble = find.byKey(const ValueKey('spotlight-bubble'));
  final next = find.byKey(const ValueKey('spotlight-next'));
  final skip = find.byKey(const ValueKey('spotlight-skip'));
  final back = find.byKey(const ValueKey('spotlight-back'));

  SpotlightScrimPainter scrimOf(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey('spotlight-scrim')),
              )
              .painter!
          as SpotlightScrimPainter;
  SpotlightArrowPainter arrowsOf(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey('spotlight-arrows')),
              )
              .painter!
          as SpotlightArrowPainter;

  SpotlightStep look() => SpotlightStep(target: target, body: 'Look at this.');
  SpotlightStep doIt() => SpotlightStep(
    target: target,
    body: 'Tap this.',
    advance: SpotlightAdvance.action,
  );

  group('spotlight: where taps go', () {
    testWidgets('a look step holds back taps on its target', (tester) async {
      await pumpStep(tester, look());

      await tester.tap(find.byKey(target), warnIfMissed: false);
      await tester.pump();

      expect(
        targetTaps,
        0,
        reason: 'looking at something must never set it off',
      );
    });

    testWidgets('an action step lets its target through', (tester) async {
      await pumpStep(tester, doIt());

      await tester.tap(find.byKey(target), warnIfMissed: false);
      await tester.pump();

      expect(targetTaps, 1, reason: 'the step asks for this tap');
    });

    testWidgets('everything outside the window is held back', (tester) async {
      await pumpStep(tester, doIt());

      await tester.tap(
        find.byKey(const ValueKey('decoy')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(decoyTaps, 0);
    });
  });

  group('spotlight: the note', () {
    testWidgets('Next and Skip do what they say', (tester) async {
      await pumpStep(tester, look());

      await tester.tap(next);
      await tester.pump();
      await tester.tap(skip);
      await tester.pump();

      expect(nexts, 1);
      expect(skips, 1);
    });

    testWidgets('Back shows from the second stop on, and goes back', (
      tester,
    ) async {
      await pumpStep(tester, look());
      expect(back, findsNothing, reason: 'nowhere to go back to yet');

      await tester.pumpWidget(harness(look(), index: 1, withBack: true));
      await tester.pump();
      await tester.tap(back);
      await tester.pump();

      expect(backs, 1);
    });

    testWidgets('an action step has no Next, only Skip', (tester) async {
      await pumpStep(tester, doIt());

      expect(next, findsNothing);
      expect(skip, findsOneWidget);
    });

    testWidgets('sits below a target near the top, without covering it', (
      tester,
    ) async {
      await pumpStep(tester, look(), where: const Alignment(0, -0.8));

      expect(
        tester.getRect(bubble).top,
        greaterThanOrEqualTo(tester.getRect(find.byKey(target)).bottom),
      );
    });

    testWidgets('sits above a target near the bottom, without covering it', (
      tester,
    ) async {
      await pumpStep(tester, look(), where: const Alignment(0, 0.8));

      expect(
        tester.getRect(bubble).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(target)).top),
      );
    });

    testWidgets('goes beside a target too tall to go above or below', (
      tester,
    ) async {
      // The navigation rail on a phone held sideways: full height, 88 wide.
      tester.view.physicalSize = const Size(891, 411);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: PraharTheme.of(Brightness.dark),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 88,
                  child: ColoredBox(key: target, color: Colors.indigo),
                ),
                Positioned.fill(
                  child: SpotlightOverlay(
                    step: look(),
                    onNext: () => nexts++,
                    onSkip: () => skips++,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      final card = tester.getRect(bubble);
      expect(
        card.left,
        greaterThanOrEqualTo(tester.getRect(find.byKey(target)).right),
      );
      expect(
        card.height,
        greaterThan(60),
        reason: 'squeezed into the sliver above or below the rail',
      );
    });
  });

  group('spotlight: the arrow', () {
    testWidgets('lands on the middle of the edge facing the note', (
      tester,
    ) async {
      await pumpStep(tester, look(), where: const Alignment(0, -0.8));

      final arrows = arrowsOf(tester).arrows;
      expect(arrows, hasLength(1));
      final aim = tester.getRect(find.byKey(target));
      expect(
        arrows.single.end.dx,
        closeTo(aim.center.dx, 0.5),
        reason: 'aimed at the middle, not a corner',
      );
      expect(
        arrows.single.end.dy,
        closeTo(
          aim.bottom + SpotlightOverlay.holePadding + SpotlightArrow.tipGap,
          0.5,
        ),
      );
      expect(
        arrows.single.start.dy,
        lessThan(tester.getRect(bubble).top),
        reason: 'it leaves from the side of the note facing the target',
      );
    });

    testWidgets('two small notes each point at their own target', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final left = GlobalKey();
      final right = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: PraharTheme.of(Brightness.dark),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 120,
                  bottom: 40,
                  width: 60,
                  height: 44,
                  child: ColoredBox(key: left, color: Colors.teal),
                ),
                Positioned(
                  left: 190,
                  bottom: 40,
                  width: 60,
                  height: 44,
                  child: ColoredBox(key: right, color: Colors.teal),
                ),
                Positioned.fill(
                  child: SpotlightOverlay(
                    step: SpotlightStep(
                      title: 'Two things',
                      body: 'One looks ahead, one looks back.',
                      companions: [
                        SpotlightCompanion(
                          target: left,
                          icon: Icons.calendar_month_outlined,
                          title: 'Left',
                          body: 'The first.',
                        ),
                        SpotlightCompanion(
                          target: right,
                          icon: Icons.track_changes_outlined,
                          title: 'Right',
                          body: 'The second.',
                        ),
                      ],
                    ),
                    stepCount: 2,
                    onNext: () => nexts++,
                    onSkip: () => skips++,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      final window = scrimOf(tester).hole!;
      final arrows = arrowsOf(tester).arrows;
      expect(arrows, hasLength(2));
      for (final (i, key) in [left, right].indexed) {
        final aim = tester.getRect(find.byKey(key));
        expect(window.contains(aim.center), isTrue, reason: 'one window');
        expect(arrows[i].end.dx, closeTo(aim.center.dx, 0.5));
        expect(
          tester.getRect(find.byKey(ValueKey('spotlight-note-$i'))).bottom,
          lessThanOrEqualTo(window.top),
        );
      }
    });
  });

  group('spotlight: between stops', () {
    testWidgets('the window slides to the next stop instead of jumping', (
      tester,
    ) async {
      await pumpStep(tester, look(), where: const Alignment(0, -0.8));
      final from = scrimOf(tester).hole!.center;

      await tester.pumpWidget(
        harness(
          SpotlightStep(target: target, body: 'Now down here.'),
          where: const Alignment(0, 0.8),
          index: 1,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));

      final to = tester.getCenter(find.byKey(target));
      final mid = scrimOf(tester).hole!.center;
      expect(mid.dy, greaterThan(from.dy + 10));
      expect(mid.dy, lessThan(to.dy - 10));

      await settle(tester);
      expect(scrimOf(tester).hole!.center.dy, closeTo(to.dy, 0.5));
    });

    testWidgets('a target that only moved is followed at once', (tester) async {
      await pumpStep(tester, look(), where: const Alignment(0, -0.8));

      // Same stop, target somewhere else: a scroll or a rotation.
      await tester.pumpWidget(harness(look(), where: const Alignment(0, 0.8)));
      await tester.pump();
      await tester.pump();

      expect(
        scrimOf(tester).hole!.center.dy,
        closeTo(tester.getCenter(find.byKey(target)).dy, 0.5),
      );
      expect(
        tester.getRect(bubble).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(target)).top),
      );
    });

    testWidgets('with reduced motion, stops swap at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpStep(tester, look(), where: const Alignment(0, -0.8));

      await tester.pumpWidget(
        harness(
          SpotlightStep(target: target, body: 'Now down here.'),
          where: const Alignment(0, 0.8),
          index: 1,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        scrimOf(tester).hole!.center.dy,
        closeTo(tester.getCenter(find.byKey(target)).dy, 0.5),
      );
      expect(arrowsOf(tester).arrows, isNotEmpty, reason: 'drawn, not drawing');
    });

    testWidgets('a stop waiting for its target holds the window still', (
      tester,
    ) async {
      await pumpStep(tester, look(), where: const Alignment(0, -0.8));
      final before = scrimOf(tester).hole;

      await tester.pumpWidget(
        harness(
          SpotlightStep(
            target: GlobalKey(),
            awaitTarget: true,
            body: 'Not built yet.',
          ),
          where: const Alignment(0, -0.8),
          index: 1,
        ),
      );
      await settle(tester);

      expect(scrimOf(tester).hole, before);
    });
  });

  group('spotlight: without a target', () {
    testWidgets('the welcome card is centred with nothing cut out', (
      tester,
    ) async {
      await pumpStep(
        tester,
        const SpotlightStep(
          title: 'Welcome to Prahar',
          body: 'A study planner.',
          nextLabel: 'Show me around',
          showMark: true,
        ),
      );

      final centre = tester.getRect(bubble).center;
      expect(centre.dx, closeTo(411 / 2, 1));
      expect(centre.dy, closeTo(914 / 2, 40));

      // Nothing is cut out, so nothing underneath can be touched.
      await tester.tap(find.byKey(target), warnIfMissed: false);
      await tester.pump();
      expect(targetTaps, 0);
    });

    testWidgets('a target that is not on screen falls back to a card', (
      tester,
    ) async {
      await pumpStep(
        tester,
        SpotlightStep(target: GlobalKey(), body: 'Nowhere to point.'),
      );

      expect(tester.takeException(), isNull);
      expect(bubble, findsOneWidget);
    });
  });

  testWidgets('spotlight fits a small phone at a large font', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpStep(
      tester,
      SpotlightStep(
        target: target,
        title: 'Add a topic',
        body:
            'A topic is usually a chapter. Give it its page count, and Prahar '
            'works out how long it will take and when to fit it in.',
      ),
      where: const Alignment(0, 0.7),
      size: const Size(320, 640),
    );

    expect(tester.takeException(), isNull);

    final card = tester.getRect(bubble);
    expect(card.left, greaterThanOrEqualTo(0));
    expect(card.right, lessThanOrEqualTo(320));
    expect(card.top, greaterThanOrEqualTo(0));
    expect(
      card.bottom,
      lessThanOrEqualTo(tester.getRect(find.byKey(target)).top),
    );
    // Scrolled out of sight inside the note, Next still has a rect on screen,
    // and a tap there lands on the dimmed layer.
    expect(tester.getRect(next).bottom, lessThanOrEqualTo(card.bottom));
  });

  testWidgets('spotlight: Back beside a long Next label never overflows', (
    tester,
  ) async {
    // Back, the dots and a label like "Show me around" together overflowed a
    // row that a width check alone judged roomy.
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        SpotlightStep(
          target: target,
          body: 'Look at this.',
          nextLabel: 'Show me around',
        ),
        where: const Alignment(0, -0.8),
        index: 1,
        withBack: true,
      ),
    );
    await settle(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'Back, the dots and Next overflowed their row',
    );
    expect(back, findsOneWidget);
    expect(
      tester.getRect(next).right,
      lessThanOrEqualTo(tester.getRect(bubble).right),
    );
  });
}
