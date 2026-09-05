import 'package:flutter/widgets.dart';

/// Where the interface stops being a column and starts being a pair of them.
///
/// One place, because a breakpoint scattered across six screens is six
/// breakpoints the first time one of them is edited. The numbers are chosen
/// from the shapes this app actually meets rather than from a chart:
///
///  * A phone held upright is ~400dp wide. One column.
///  * The same phone turned sideways is ~890 x 410. Wide enough for two
///    columns, and *short* enough that a 68dp bottom bar plus a 60dp app bar
///    is a fifth of the screen — which is why landscape switches to a rail.
///  * A tablet is wide in both orientations, and tall enough not to care.
///
/// So width decides the number of columns and height decides where navigation
/// goes. They are separate questions and conflating them puts a rail on a
/// tall tablet in portrait, where the bottom bar is perfectly good.
class Layout {
  const Layout._();

  /// Two columns at or above this width.
  static const wideWidth = 720.0;

  /// Below this height, vertical space is the scarce resource.
  static const shortHeight = 500.0;

  static bool isWide(Size size) => size.width >= wideWidth;

  static bool isShort(Size size) => size.height < shortHeight;

  /// Navigation moves to the side when the screen is short *and* there is
  /// width to spare for it — landscape on a phone, mainly. A tall tablet keeps
  /// the bottom bar, which is easier to reach than a rail.
  static bool usesRail(Size size) => isWide(size) && isShort(size);

  /// A single column of text and cards stops being readable long before it
  /// stops being wide. Content is capped and centred rather than stretched
  /// across a tablet.
  static const readableWidth = 620.0;
}

/// Caps a column's width and centres it, for screens that are one list however
/// wide the window gets — Progress, Settings, a topic list.
class ReadableColumn extends StatelessWidget {
  const ReadableColumn({super.key, required this.child, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? Layout.readableWidth),
      child: child,
    ),
  );
}
