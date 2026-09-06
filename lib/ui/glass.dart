import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/preferences.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Frosted-glass surfaces.
///
/// One primitive so every glass surface in the app agrees on blur radius,
/// tint opacity and border. Consistency is what makes multiple pieces of
/// glass feel like the same material rather than a random collection of
/// blurred rectangles.
///
/// Applied sparingly — the bottom nav, modal sheets, the Today header, the
/// feasibility banner and the subject-detail status panel. Contrast between
/// glass and matte is where the "premium" reads from; putting glass on every
/// surface flattens the effect. Cards, list rows and Progress stay matte.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.tintAlpha,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  /// Overrides the theme-derived tint. Useful for a slightly warmer nav bar,
  /// say, without introducing a second primitive.
  final Color? tint;

  /// Overrides just the *opacity* of the theme-derived tint, keeping its
  /// colour. The default is deliberately thin; raise it for a surface that has
  /// to carry dense text over busy content.
  final double? tintAlpha;

  static const _sigma = 24.0; // radius that reads as "frosted", not "smeared"

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 0.28, arrived at twice. The original 0.55/0.60 had the tint carrying the
    // surface with the blur as decoration; 0.42/0.45 was better; the app bar
    // was then tried at 0.28 and that is the one that reads as *glass* rather
    // than as a panel that happens to blur, so every surface now uses it.
    //
    // The trade is real and accepted: this thin, text sitting on the glass has
    // to hold its own against whatever scrolls under it. It does here because
    // the glass surfaces carry short, high-contrast text — a wordmark, a date,
    // a verdict — over the app's own quiet backgrounds. Putting dense body
    // copy on glass would need [tintAlpha] to push it back up.
    final base = tint ?? scheme.surface.withValues(alpha: tintAlpha ?? 0.28);

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
    final glass =
        context.select<AppState, MaterialChoice>(
          (s) => s.prefs.materialChoice,
        ) ==
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

/// A panel that answers to both Settings > Materials and Settings > Cards.
///
/// Extracted from Today's hero because Look needs the identical thing: a
/// surface that demonstrably *is* the current look. Hand-rolling a second one
/// is how the first version of Look's header ended up ignoring the card style
/// entirely — a Container with its own border looks convincing and reflects
/// nothing, which is the trap CLAUDE.md warns about in as many words.
///
/// The three cases, and why:
///
///  * **Matte** — a plain Card. It has always answered to the style, because
///    the style is the Card theme.
///  * **Glass, Open** — no panel at all. "No card" cannot quietly mean one.
///  * **Glass, anything else** — a transparent Card for its shadow and
///    geometry, the blur inside it, and the edge drawn *over* the top. A Card
///    paints its outline beneath its child, so a filled child hides it; that
///    is why the hairline never appeared on the glass hero until it was moved
///    to a foreground decoration.
class StyledPanel extends StatelessWidget {
  const StyledPanel({super.key, required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = context.select<AppState, Prefs>((s) => s.prefs);
    final glass = prefs.materialChoice == MaterialChoice.glass;
    final style = prefs.cardStyle;

    if (!glass) {
      return Card(child: Padding(padding: padding, child: child));
    }
    if (style == CardStyle.open) {
      return Padding(padding: padding, child: child);
    }

    final cards = theme.cardTheme;
    final radius = BorderRadius.circular(PraharTheme.cardRadius);

    // Taken from the style rather than read back off the theme's ShapeBorder:
    // that introspection returned no side at runtime even where the theme
    // plainly had one.
    final side = style == CardStyle.hairline
        ? BorderSide(color: theme.colorScheme.outlineVariant, width: 1)
        : BorderSide.none;

    return Card(
      color: Colors.transparent,
      shadowColor: cards.shadowColor,
      elevation: cards.elevation ?? 0,
      shape: cards.shape,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: side.style == BorderStyle.none
              ? null
              : Border.fromBorderSide(side),
        ),
        child: GlassSurface(
          borderRadius: radius,
          padding: padding,
          // Tinted washes its fill through the card; taking that colour at the
          // standard glass alpha keeps the wash without a second number.
          tint: style == CardStyle.tinted
              ? cards.color?.withValues(alpha: 0.28)
              : null,
          child: child,
        ),
      ),
    );
  }
}

/// How much room a screen must leave at the *bottom* of its scroll view.
///
/// 90 was hardcoded in every list in the app: the height of the navigation
/// bar on the developer's phone, which uses gesture navigation. A phone with
/// the three-button bar turned on — a setting, not a rare device, and the
/// default on plenty of Samsungs and Motorolas — puts roughly another 48dp of
/// system bar underneath, and in glass the body runs behind all of it. The
/// last item of every list was sitting under the navigation.
///
/// `viewPadding` rather than `padding`: Scaffold removes `padding` from the
/// body it lays out, but `viewPadding` keeps reporting the physical inset,
/// which is the number wanted here.
///
/// Only added under glass. In matte the scaffold stops the body above the bar
/// and the 90 is already generous.
double navBottomInset(BuildContext context) {
  final glass =
      context.select<AppState, MaterialChoice>(
        (s) => s.prefs.materialChoice,
      ) ==
      MaterialChoice.glass;
  return glass ? 90 + MediaQuery.viewPaddingOf(context).bottom : 90;
}

/// How much room a screen must leave at the top of its scroll view when the
/// app bar is glass.
///
/// Glass only reads as glass if content passes *underneath* it, so the
/// scaffold extends the body behind the bar and every screen becomes
/// responsible for starting its own content below it. Skip this and the first
/// line of the screen spends its life under the title — which is not a crash,
/// not a test failure, and invisible until someone looks at the device.
///
/// Returns zero in matte, where the bar is opaque and the body stops at it.
/// Use it on the top-level scroll view of a screen, never on a card inside
/// one: the inset is a property of the screen's relationship to the bar.
double glassTopInset(BuildContext context) {
  final glass =
      context.select<AppState, MaterialChoice>(
        (s) => s.prefs.materialChoice,
      ) ==
      MaterialChoice.glass;
  if (!glass) return 0;

  // Just the padding, and deliberately not `padding.top + toolbarHeight`.
  //
  // Scaffold hands a body that extends behind the app bar a MediaQuery whose
  // `padding.top` is *already* the whole bar — status bar plus toolbar —
  // precisely so scroll views can inset themselves. Adding the toolbar height
  // again insets twice, which is what Today did from the day it shipped: 60dp
  // of dead space under the wordmark, in glass only. It looked like a design
  // choice, which is why it survived a month of looking at it.
  //
  // `test/glass_inset_test.dart` pins this by measuring against matte, where
  // the scaffold does the same job with no help. The two must land together.
  return MediaQuery.paddingOf(context).top;
}
