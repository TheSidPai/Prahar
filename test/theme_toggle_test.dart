import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/domain/preferences.dart';
import 'package:prahar/ui/settings_screen.dart';
import 'package:prahar/ui/theme.dart';

/// Is the moving pill actually under the label it selects?
///
/// This was "fixed" twice by reasoning about the arithmetic and looking at a
/// screenshot, and both times it was still visibly wrong. Eyes are bad at
/// tens of pixels and arithmetic is easy to get confidently wrong; measuring
/// the two rectangles is neither.
void main() {
  Widget harness(ThemeChoice selected) => MaterialApp(
    theme: PraharTheme.of(Brightness.dark),
    home: Scaffold(
      body: Padding(
        // The real screen puts it in 16dp of horizontal padding.
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ThemeToggle(selected: selected, onChanged: (_) {}),
        ),
      ),
    ),
  );

  for (final (choice, label) in [
    (ThemeChoice.light, 'Light'),
    (ThemeChoice.system, 'Auto'),
    (ThemeChoice.dark, 'Dark'),
  ]) {
    testWidgets('the pill sits on $label', (tester) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(choice));
      await tester.pumpAndSettle();

      final pill = tester.getRect(find.byType(AnimatedPositioned));

      // The icon and the word together, not the word alone. A segment holds
      // an 18px glyph and a 6px gap before its text, so the text's own centre
      // is 12px right of the segment's — in all three, identically. Measuring
      // the text made a correct layout look 12px wrong and sent the fix
      // chasing arithmetic that was already right.
      final content = tester.getRect(
        find.ancestor(of: find.text(label), matching: find.byType(FittedBox)),
      );

      expect(
        content.center.dx,
        closeTo(pill.center.dx, 1.0),
        reason:
            'the selector is not centred on its label, horizontally\n'
            'pill:    $pill\n'
            'content: $content',
      );

      // The axis that was actually wrong, and went unnoticed through three
      // attempts at the other one. A Stack top-aligns anything it is not
      // positioning, so the labels sat high in the track while every
      // horizontal assertion here passed.
      expect(
        content.center.dy,
        closeTo(pill.center.dy, 1.0),
        reason:
            'the selector is not centred on its label, vertically\n'
            'pill:    $pill\n'
            'content: $content',
      );
    });
  }

  testWidgets('the pill stays inside the track', (tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(ThemeChoice.dark));
    await tester.pumpAndSettle();

    // The track is the outermost box the toggle draws.
    final track = tester.getRect(find.byType(ThemeToggle));
    final pill = tester.getRect(find.byType(AnimatedPositioned));

    expect(
      pill.right,
      lessThanOrEqualTo(track.right),
      reason: 'the pill hangs off the end of the track',
    );
    expect(pill.left, greaterThanOrEqualTo(track.left));
  });
}
