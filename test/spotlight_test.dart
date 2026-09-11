import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/ui/spotlight.dart';
import 'package:prahar/ui/theme.dart';

/// The spotlight on its own, before any tour uses it.
///
/// What is pinned here is what makes a tour feel finished or broken: taps go
/// where the step says and nowhere else, the bubble never covers the thing it
/// is talking about, the window follows its target, and nothing throws when a
/// target is missing or the font is large.
void main() {
  late GlobalKey target;
  late int targetTaps;
  late int decoyTaps;
  late int nexts;
  late int skips;

  setUp(() {
    target = GlobalKey();
    targetTaps = 0;
    decoyTaps = 0;
    nexts = 0;
    skips = 0;
  });

  Widget harness(SpotlightStep step, {Alignment where = Alignment.center}) {
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
                onNext: () => nexts++,
                onSkip: () => skips++,
              ),
            ),
          ],
        ),
      ),
    );
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
    // One frame to lay out, one for the post-frame measurement to land, and
    // time for the fade and the welcome mark to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
  }

  final bubble = find.byKey(const ValueKey('spotlight-bubble'));
  final next = find.byKey(const ValueKey('spotlight-next'));
  final skip = find.byKey(const ValueKey('spotlight-skip'));

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

  group('spotlight: the bubble', () {
    testWidgets('Next and Skip do what they say', (tester) async {
      await pumpStep(tester, look());

      await tester.tap(next);
      await tester.pump();
      await tester.tap(skip);
      await tester.pump();

      expect(nexts, 1);
      expect(skips, 1);
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

    testWidgets('moves when its target moves', (tester) async {
      await pumpStep(tester, look(), where: const Alignment(0, -0.8));
      final before = tester.getRect(bubble);

      // Same key, new place, as after a rotation or a sheet closing.
      await tester.pumpWidget(harness(look(), where: const Alignment(0, 0.8)));
      await tester.pump();
      await tester.pump();

      final after = tester.getRect(bubble);
      expect(
        after.bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(target)).top),
      );
      expect(after, isNot(before));
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

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
    // Scrolled out of sight inside the bubble, Next still has a rect on
    // screen, and a tap there lands on the dimmed layer.
    expect(tester.getRect(next).bottom, lessThanOrEqualTo(card.bottom));
  });
}
