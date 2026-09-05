import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Prahar mark, drawn with the same proportions as the launcher icon.
///
/// A CustomPainter rather than a bundled PNG so it scales cleanly to any size
/// and can adapt colours to the current theme without carrying multiple
/// asset variants. The launcher icon and this widget speak the same visual
/// language, so anywhere the app introduces itself feels of a piece.
///
/// Two flavours:
///  * [PraharMark]        — the mark only, transparent background
///  * [PraharMarkFilled]  — the mark on the dawn gradient, matching the icon
///
/// Palettes are theme-aware by default. `onDark` (the icon palette) is used
/// on any dark surface; `onLight` swaps ink and pivot for legibility on
/// light surfaces. Callers may override the palette entirely with [palette].
class PraharMark extends StatelessWidget {
  const PraharMark({super.key, this.size = 32, this.palette});

  final double size;
  final MarkPalette? palette;

  @override
  Widget build(BuildContext context) {
    final resolved =
        palette ??
        (Theme.of(context).brightness == Brightness.dark
            ? MarkPalette.onDark
            : MarkPalette.onLight);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(resolved)),
    );
  }
}

class PraharMarkFilled extends StatelessWidget {
  const PraharMarkFilled({super.key, this.size = 48, this.borderRadius = 12});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // Reuses the exact gradient and angle of the launcher icon, so a filled
    // mark placed in the app reads as the same object the phone shows on the
    // home screen.
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF201E42), Color(0xFFDC764E)],
          ),
        ),
        child: CustomPaint(painter: _MarkPainter(MarkPalette.onDark)),
      ),
    );
  }
}

/// The mark plus the "Prahar" wordmark. Used where the app introduces itself
/// — the first-run today screen, the top of the guide, the settings footer.
class PraharLogo extends StatelessWidget {
  const PraharLogo({
    super.key,
    this.markSize = 34,
    this.filled = true,
    this.wordmarkStyle,
  });

  final double markSize;

  /// Filled mark (with dawn gradient behind) reads as a brand moment;
  /// the flat mark reads as a decorative header. Filled is the default
  /// because it matches the launcher icon exactly.
  final bool filled;

  final TextStyle? wordmarkStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (filled)
          PraharMarkFilled(size: markSize, borderRadius: markSize * 0.28)
        else
          PraharMark(size: markSize),
        SizedBox(width: markSize * 0.35),
        Text(
          'Prahar',
          style:
              wordmarkStyle ??
              theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                fontSize: markSize * 0.72,
              ),
        ),
      ],
    );
  }
}

/// The five colours the mark uses.
///
/// Preset instances match the launcher-icon palette on dark backgrounds and
/// invert cream-vs-dark on light backgrounds so the pivot and sun stay
/// legible either way.
@immutable
class MarkPalette {
  final Color sun;
  final Color hand;
  final Color pivot;
  final Color tick;
  final double tickAlpha;

  const MarkPalette({
    required this.sun,
    required this.hand,
    required this.pivot,
    required this.tick,
    this.tickAlpha = 0.53, // 135/255 — matches K4 tuning
  });

  /// The launcher-icon palette. Cream sun over a dark ground, amber hand,
  /// near-black pivot, pale ticks. Use on any dark surface.
  static const onDark = MarkPalette(
    sun: Color(0xFFFAD294),
    hand: Color(0xFFF69460),
    pivot: Color(0xFF3C2828),
    tick: Color(0xFFF5F4FC),
  );

  /// For placement on light surfaces. The sun keeps its warmth so the mark
  /// still reads as Prahar; ticks darken so they are visible against a light
  /// background instead of disappearing.
  ///
  /// The first attempt at this used a mid-grey at 55%, which is the same
  /// relationship the dark palette has to its own background — and it was
  /// nearly invisible. Pale strokes on a dark ground bloom; dark strokes on a
  /// white one do not, so light mode needs both a darker ink and near-full
  /// alpha to arrive at the same apparent weight.
  static const onLight = MarkPalette(
    sun: Color(0xFFF6A662),
    hand: Color(0xFFD9612F),
    pivot: Color(0xFF2A2032),
    tick: Color(0xFF4A4460),
    tickAlpha: 0.92,
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.palette);

  final MarkPalette palette;

  @override
  void paint(Canvas canvas, Size s) {
    // The proportions below come straight from tools/make_icon.ps1 — sun at
    // 0.26r, ticks at 0.3545..0.4018r, hand stroke 0.0355s ending at 0.78 of
    // the sun radius, pivot 0.0236s. Keeping them literal means the two
    // artefacts (PNG icon, Flutter mark) can never drift out of alignment.
    //
    // Every number is the original T3+K4 tuning multiplied by 0.26/0.22 =
    // 1.182 — a uniform zoom, not a retune. If the mark is ever rescaled
    // again, scale all six together or the two artefacts stop matching.
    //
    // One deliberate departure: the two stroke widths have a floor in logical
    // pixels. The proportions were tuned on a 1024px master that is then
    // downsampled, where 0.0165 of the side is a 17px stroke. In the app the
    // mark is drawn at 24 to 56px, where the same fraction is 0.4 to 0.9px —
    // a sub-pixel line that anti-aliases to a ghost, which is why the hour
    // ticks were invisible in light mode. The floors bind only below about
    // 76px and converge to the tuned ratio above it, so the launcher icon,
    // rendered at 1024, is untouched by them.
    final side = s.shortestSide;
    final cx = s.width / 2;
    final cy = s.height / 2;
    final rIn = side * 0.3545;
    final rOut = side * 0.4018;
    final sunR = side * 0.26;
    final pivotR = side * 0.0236;

    final tickPaint = Paint()
      ..color = palette.tick.withValues(alpha: palette.tickAlpha)
      ..strokeWidth = math.max(side * 0.0165, 1.0)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = math.pi * 2 * (i / 12.0) - math.pi / 2;
      canvas.drawLine(
        Offset(cx + math.cos(a) * rIn, cy + math.sin(a) * rIn),
        Offset(cx + math.cos(a) * rOut, cy + math.sin(a) * rOut),
        tickPaint,
      );
    }

    canvas.drawCircle(Offset(cx, cy), sunR, Paint()..color = palette.sun);

    final handAngle = math.pi * 2 * (2 / 12.0) - math.pi / 2;
    final handPaint = Paint()
      ..color = palette.hand
      // Floored too, and higher than the ticks: without it the hand would end
      // up thinner than they are at 24px and the hierarchy would invert.
      ..strokeWidth = math.max(side * 0.0355, 1.4)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(
        cx + math.cos(handAngle) * sunR * 0.78,
        cy + math.sin(handAngle) * sunR * 0.78,
      ),
      handPaint,
    );

    canvas.drawCircle(Offset(cx, cy), pivotR, Paint()..color = palette.pivot);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.palette != palette;
}
