import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/preferences.dart';
import '../state/app_state.dart';

/// Frosted-glass surfaces.
///
/// One primitive so every glass surface in the app agrees on blur radius,
/// tint opacity and border. Consistency is what makes multiple pieces of
/// glass feel like the same material rather than a random collection of
/// blurred rectangles.
///
/// Applied sparingly — only the bottom nav, modal sheets, and the Today
/// header. Contrast between glass and matte is where the "premium" reads
/// from; putting glass on every surface flattens the effect.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding = EdgeInsets.zero,
    this.tint,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  /// Overrides the theme-derived tint. Useful for a slightly warmer nav bar,
  /// say, without introducing a second primitive.
  final Color? tint;

  static const _sigma = 24.0; // radius that reads as "frosted", not "smeared"

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = tint ??
        (Theme.of(context).brightness == Brightness.dark
            // A hair of the surface colour so the blur has something to tint,
            // not a heavy panel — the point is to see the layer beneath.
            ? scheme.surface.withValues(alpha: 0.55)
            : scheme.surface.withValues(alpha: 0.60));

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma),
        child: Container(
          decoration: BoxDecoration(
            color: base,
            borderRadius: borderRadius,
            border: Border.all(
              // A hairline top-edge highlight sells the "material" impression.
              color: scheme.onSurface.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Wraps a modal-sheet [child] in a glass panel when the pref is on, or a
/// plain surface-coloured panel when matte. Every sheet in the app should use
/// this rather than draw its own background; the theme leaves the sheet
/// transparent so this wrapper is what actually paints.
///
/// A single widget centralises the shape and top-only rounded corners so the
/// two materials never disagree about them.
class SheetBackground extends StatelessWidget {
  const SheetBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final glass = context.select<AppState, MaterialChoice>(
            (s) => s.prefs.materialChoice) ==
        MaterialChoice.glass;
    const shape = BorderRadius.vertical(top: Radius.circular(24));

    if (!glass) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(borderRadius: shape),
        child: child,
      );
    }
    return GlassSurface(borderRadius: shape, child: child);
  }
}

