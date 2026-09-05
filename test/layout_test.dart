import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/ui/layout.dart';

/// Breakpoints, pinned at the shapes this app actually meets.
///
/// Tested rather than eyeballed because the interesting cases are the ones
/// that are awkward to reproduce by hand: a phone on its side is wide and
/// short at once, and it is the *combination* that decides where navigation
/// goes.
void main() {
  // Xiaomi 23127PN0CG, the device this is developed against.
  const phonePortrait = Size(411, 891);
  const phoneLandscape = Size(891, 411);
  const tabletPortrait = Size(834, 1194);
  const tabletLandscape = Size(1194, 834);
  const foldClosed = Size(360, 780);

  group('columns follow width', () {
    test('a phone upright is one column', () {
      expect(Layout.isWide(phonePortrait), isFalse);
      expect(Layout.isWide(foldClosed), isFalse);
    });

    test('a phone on its side is two', () {
      expect(Layout.isWide(phoneLandscape), isTrue);
    });

    test('a tablet is two in both orientations', () {
      expect(Layout.isWide(tabletPortrait), isTrue);
      expect(Layout.isWide(tabletLandscape), isTrue);
    });
  });

  group('navigation follows height as well', () {
    test('a phone on its side gets the rail — vertical space is scarce', () {
      // 411dp tall: a 60dp app bar and a 68dp bottom bar would eat a third
      // of it before any content is drawn.
      expect(Layout.usesRail(phoneLandscape), isTrue);
    });

    test('a tablet keeps the bottom bar, which is easier to reach', () {
      expect(Layout.usesRail(tabletPortrait), isFalse);
      expect(Layout.usesRail(tabletLandscape), isFalse);
    });

    test('a phone upright keeps the bottom bar', () {
      expect(Layout.usesRail(phonePortrait), isFalse);
    });

    test('narrow and short still gets no rail — there is no width for one', () {
      expect(Layout.usesRail(const Size(600, 400)), isFalse);
    });
  });

  test('the boundaries themselves are inclusive where it matters', () {
    expect(Layout.isWide(const Size(Layout.wideWidth, 800)), isTrue);
    expect(Layout.isWide(const Size(Layout.wideWidth - 1, 800)), isFalse);
    expect(Layout.isShort(const Size(900, Layout.shortHeight)), isFalse);
    expect(Layout.isShort(const Size(900, Layout.shortHeight - 1)), isTrue);
  });

  testWidgets('ReadableColumn caps its child rather than stretching it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ReadableColumn(child: SizedBox.expand()),
      ),
    );

    final box = tester.getSize(find.byType(SizedBox));
    expect(box.width, Layout.readableWidth);
  });
}
