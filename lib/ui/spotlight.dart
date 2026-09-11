import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'brand.dart';
import 'theme.dart';

/// How a spotlight step moves on.
enum SpotlightAdvance {
  /// The bubble has a Next button, and the highlighted target is shown but
  /// can't be touched. Looking at something must never set it off.
  next,

  /// The tour waits for the student to do the thing. There is no Next button;
  /// the highlighted target is the only touchable part of the screen, and
  /// whatever owns the step decides when it has been done.
  ///
  /// This is what makes it a do-tour rather than a look-tour. On a fresh
  /// install there is nothing on Subjects or Today to point at, so the tour
  /// has to have the student create it.
  action,
}

/// One stop on a tour.
@immutable
class SpotlightStep {
  const SpotlightStep({
    required this.body,
    this.title,
    this.target,
    this.advance = SpotlightAdvance.next,
    this.nextLabel = 'Next',
    this.showMark = false,
    this.extra,
  });

  /// The widget to highlight, found through the GlobalKey placed on it.
  ///
  /// Null centres the bubble with nothing cut out, which is the welcome card's
  /// shape. A key that isn't currently on screen gets the same centred bubble
  /// rather than an error, so a layout that lacks a target degrades to a card.
  final GlobalKey? target;

  final String? title;
  final String body;
  final SpotlightAdvance advance;
  final String nextLabel;

  /// Draws the brand mark above the title, for the welcome card.
  final bool showMark;

  /// Anything more the stop needs under its words, such as a checklist. It
  /// scrolls with the words; the buttons stay pinned below both.
  final Widget? extra;
}

/// A dimmed layer over the whole app with a rounded window onto one widget,
/// and a bubble explaining it.
///
/// It is meant to sit in a Stack above the app's own content, as the top child.
/// It only draws and decides where taps go; which step is showing, and when a
/// step is finished, belongs to whatever places it.
///
/// Three rules are what make it feel finished rather than bolted on:
///
///  * **The bubble never covers its own target.** It goes on whichever side of
///    the window has more room, is clamped to the screen, and scrolls when a
///    large font makes it taller than the space it was given.
///  * **The window follows the target.** It is re-measured after every frame
///    that happens, so it tracks a rotation, a scroll, or a sheet sliding away.
///    It does not run a frame loop of its own: when nothing on screen changes,
///    nothing is re-measured and the phone is left alone.
///  * **Taps go where the step says.** Everywhere outside the window is held
///    back. Inside it, taps reach the target only on an action step.
class SpotlightOverlay extends StatefulWidget {
  const SpotlightOverlay({
    super.key,
    required this.step,
    required this.onSkip,
    this.onNext,
    this.skipLabel = 'Skip',
  });

  final SpotlightStep step;
  final VoidCallback onSkip;

  /// Called by the Next button. Ignored on action steps, which have none.
  final VoidCallback? onNext;

  final String skipLabel;

  /// Room left around the target inside the window, so its edges aren't
  /// clipped by the ring.
  static const holePadding = 8.0;
  static const holeRadius = 16.0;

  /// Distance from the screen's edges, inside the safe area.
  static const margin = 16.0;

  /// Space between the window and the bubble.
  static const gap = 14.0;

  static const maxBubbleWidth = 360.0;

  /// Less room than this above and below a target, and the bubble goes beside
  /// it instead.
  static const minBubbleHeight = 160.0;

  @override
  State<SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<SpotlightOverlay> {
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// Finds the target and, after the next frame, looks again.
  ///
  /// A post-frame callback never schedules a frame by itself, so this chain
  /// only turns over while something else is drawing: an animation, a scroll,
  /// a rotation. When the screen is still, it waits, which a Ticker would not.
  void _measure() {
    if (!mounted) return;
    final next = _targetRect();
    if (next != _hole) setState(() => _hole = next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  Rect? _targetRect() {
    final target = widget.step.target?.currentContext?.findRenderObject();
    final self = context.findRenderObject();
    if (target is! RenderBox || !target.attached || !target.hasSize) {
      return null;
    }
    if (self is! RenderBox || !self.hasSize) return null;

    final topLeft = self.globalToLocal(target.localToGlobal(Offset.zero));
    return (topLeft & target.size).inflate(SpotlightOverlay.holePadding);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = widget.step;
    final hole = _hole;

    // Black at different strengths per theme: the dark theme is already
    // nearly black, so a light scrim over it barely reads as dimmed.
    final scrim = Colors.black.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.72 : 0.56,
    );

    final bubble = _Bubble(
      key: const ValueKey('spotlight-bubble'),
      step: step,
      onNext: widget.onNext,
      onSkip: widget.onSkip,
      skipLabel: widget.skipLabel,
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          final safe = MediaQuery.paddingOf(context);
          const margin = SpotlightOverlay.margin;
          final width = math.min(
            SpotlightOverlay.maxBubbleWidth,
            math.max(0.0, size.width - margin * 2),
          );

          final Widget placed;
          if (hole == null) {
            placed = Positioned.fill(
              child: Center(
                child: SizedBox(
                  width: width,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(
                        0.0,
                        size.height - safe.vertical - margin * 2,
                      ),
                    ),
                    child: bubble,
                  ),
                ),
              ),
            );
          } else {
            final top = safe.top + margin;
            final bottom = size.height - safe.bottom - margin;
            final spaceBelow = bottom - (hole.bottom + SpotlightOverlay.gap);
            final spaceAbove = (hole.top - SpotlightOverlay.gap) - top;
            final spaceLeft =
                (hole.left - SpotlightOverlay.gap) - (safe.left + margin);
            final spaceRight =
                (size.width - safe.right - margin) -
                (hole.right + SpotlightOverlay.gap);
            final vertical = math.max(spaceAbove, spaceBelow);
            final sideways = math.max(spaceLeft, spaceRight);
            final below = spaceBelow >= spaceAbove;

            if (vertical < SpotlightOverlay.minBubbleHeight &&
                sideways > vertical) {
              // A target as tall as the screen, like the navigation rail,
              // leaves no room above or below it, so the bubble goes beside.
              final right = spaceRight >= spaceLeft;
              final along = bottom - top;
              final y = along <= 0
                  ? 0.0
                  : ((hole.center.dy - top) / along * 2 - 1).clamp(-1.0, 1.0);
              placed = Positioned(
                top: top,
                height: math.max(0.0, along),
                left: right ? hole.right + SpotlightOverlay.gap : null,
                right: right
                    ? null
                    : size.width - hole.left + SpotlightOverlay.gap,
                width: math.min(width, sideways),
                child: Align(alignment: Alignment(0, y), child: bubble),
              );
            } else {
              // Centred on the target where it can be, pushed back inside the
              // screen where it can't.
              final maxLeft = math.max(margin, size.width - margin - width);
              final left = (hole.center.dx - width / 2).clamp(margin, maxLeft);

              placed = Positioned(
                left: left,
                width: width,
                top: below ? hole.bottom + SpotlightOverlay.gap : null,
                bottom: below
                    ? null
                    : size.height - hole.top + SpotlightOverlay.gap,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(0.0, below ? spaceBelow : spaceAbove),
                  ),
                  child: bubble,
                ),
              );
            }
          }

          return Stack(
            children: [
              Positioned.fill(
                child: _PassThroughHole(
                  hole: step.advance == SpotlightAdvance.action ? hole : null,
                  // Opaque and empty: a tap anywhere on the scrim is caught
                  // here and goes nowhere.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: CustomPaint(
                      painter: _ScrimPainter(
                        hole: hole,
                        scrim: scrim,
                        ring: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              placed,
            ],
          );
        },
      ),
    );
  }
}

/// The card the words sit on.
///
/// A surface of its own rather than StyledPanel, deliberately. StyledPanel
/// follows Settings > Cards, and under the Open style in Glass it draws no
/// surface at all. That is right for a row in a list and wrong for words
/// floating over a dimmed screen, which would have nothing behind them.
class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.step,
    required this.onSkip,
    required this.skipLabel,
    this.onNext,
  });

  final SpotlightStep step;
  final VoidCallback onSkip;
  final VoidCallback? onNext;
  final String skipLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final centred = step.showMark;
    final showNext = step.advance == SpotlightAdvance.next && onNext != null;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        elevation: 8,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(PraharTheme.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Only the words scroll. The buttons stay pinned below them:
            // otherwise, at a large font on a small phone, the one way forward
            // is scrolled out of sight inside a card that gives no sign it
            // scrolls at all.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: centred
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.stretch,
                  children: [
                    if (step.showMark) ...[
                      const AnimatedPraharMark(size: 56),
                      const SizedBox(height: 14),
                    ],
                    if (step.title != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          step.title!,
                          textAlign: centred
                              ? TextAlign.center
                              : TextAlign.start,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        step.body,
                        textAlign: centred ? TextAlign.center : TextAlign.start,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                    ?step.extra,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              // Wrap rather than a Row with a Spacer: at a large font on a
              // narrow phone the two buttons don't fit side by side, and a
              // Spacer does not stop a Row overflowing.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: const ValueKey('spotlight-skip'),
                    onPressed: onSkip,
                    child: Text(skipLabel),
                  ),
                  if (showNext)
                    // Filled, so amber: moving on is the call to action here.
                    FilledButton(
                      key: const ValueKey('spotlight-next'),
                      onPressed: onNext,
                      child: Text(step.nextLabel),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets taps inside [hole] fall through to whatever is underneath.
///
/// Reporting "no hit" inside the window is what hands the tap to the next
/// widget down the Stack, which is the app. Everywhere else the child is hit
/// normally, and the child catches and discards it.
class _PassThroughHole extends SingleChildRenderObjectWidget {
  const _PassThroughHole({required this.hole, super.child});

  final Rect? hole;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPassThroughHole(hole);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPassThroughHole renderObject,
  ) {
    renderObject.hole = hole;
  }
}

class _RenderPassThroughHole extends RenderProxyBox {
  _RenderPassThroughHole(this.hole);

  Rect? hole;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hole != null && hole!.contains(position)) return false;
    return super.hitTest(result, position: position);
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.hole, required this.scrim, required this.ring});

  final Rect? hole;
  final Color scrim;

  /// Indigo, from the theme's primary: in this app indigo means focus.
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final window = hole;
    if (window == null) {
      canvas.drawPath(screen, Paint()..color = scrim);
      return;
    }

    final shape = RRect.fromRectAndRadius(
      window,
      const Radius.circular(SpotlightOverlay.holeRadius),
    );
    canvas.drawPath(
      Path.combine(PathOperation.difference, screen, Path()..addRRect(shape)),
      Paint()..color = scrim,
    );

    // A soft halo first, then a thin, crisp ring on top of it.
    canvas.drawRRect(
      shape.inflate(2),
      Paint()
        ..color = ring.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.scrim != scrim || old.ring != ring;
}
