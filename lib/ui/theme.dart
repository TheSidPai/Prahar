import 'package:flutter/material.dart';

import '../domain/preferences.dart';

/// The visual language: restrained, quiet, and legible at a glance.
///
/// The aim is elegance rather than decoration. Three rules do most of the work:
///
///  * **One accent.** Colour marks subjects and the single most important
///    action. Everything else is a neutral, so a coloured element always means
///    something.
///  * **Outlines, not fills.** Cards are surface-coloured with a hairline
///    border rather than a lighter grey block. Filled greys stack into visual
///    noise once several cards sit together.
///  * **Hierarchy through weight and spacing, not size.** Headings are barely
///    larger than body text; they read as headings because of weight, letter
///    spacing and the room around them.
class PraharTheme {
  const PraharTheme._();

  /// A deep, slightly desaturated indigo. Saturated blues read as "tech
  /// product"; muting it lets subject colours stand out against it.
  static const seed = Color(0xFF5A63D8);

  /// Amber, the warm accent.
  ///
  /// The launcher icon and both home-screen widgets have always been warm —
  /// navy ground, amber hand, amber progress bar — while the interior was
  /// cool indigo with no amber anywhere, so the app and its own icon read as
  /// two different products. The split is now by *meaning* rather than by
  /// artefact: indigo stays structural (navigation, selection, focus, "this
  /// is today"), and amber marks effort and intent — the streak, the block
  /// happening right now, and the one button that is the point of a screen.
  ///
  /// The value is taken from the icon itself, between its sun (0xFFFAD294)
  /// and its hand (0xFFF69460).
  static const accent = Color(0xFFF0A055);

  /// Ink for anything drawn *on* [accent]. Dark rather than white: amber is a
  /// light colour and white on it fails contrast at label sizes in both
  /// themes, which is how amber buttons usually end up looking cheap.
  static const accentInk = Color(0xFF2A1A0E);

  /// Amber used *as text* on a light surface. [accent] is too pale to read
  /// against white, so light mode borrows the mark's darker hand colour —
  /// the same one `MarkPalette.onLight` uses, for the same reason.
  static const accentOnLight = Color(0xFFC2661F);

  /// The one bundled family. A seven-font picker shipped while the choice was
  /// still open; Inter won it on a live preview, so the picker and the six
  /// unused TTFs are gone. Bundled, never fetched — the release build has no
  /// INTERNET permission and a runtime fetch silently yields the system font.
  static const fontFamily = 'Inter';

  static ThemeData of(
    Brightness brightness, {
    MaterialChoice material = MaterialChoice.matte,
  }) {
    final dark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    ).copyWith(
      // Near-black rather than true black: true black crushes the card
      // borders and makes the whole screen feel like a void.
      surface: dark ? const Color(0xFF101216) : const Color(0xFFFBFBFC),
      surfaceContainerLowest:
          dark ? const Color(0xFF0C0E12) : const Color(0xFFFFFFFF),
      surfaceContainer: dark ? const Color(0xFF171A20) : const Color(0xFFFFFFFF),
      surfaceContainerHighest:
          dark ? const Color(0xFF1C2027) : const Color(0xFFF2F3F5),
      outlineVariant: dark
          ? const Color(0xFF2A2F38)
          : const Color(0xFFE3E5EA),

      // Amber lives in the scheme rather than in a constant each widget
      // imports, so "the accent" is reachable from any BuildContext and can
      // never be half-applied. `tertiary` is amber-as-text and so differs by
      // brightness; the containers stay pale/deep in the M3 sense, because
      // the text drawn on them is ordinary onSurface text.
      tertiary: dark ? const Color(0xFFF3A968) : accentOnLight,
      onTertiary: accentInk,
      tertiaryContainer:
          dark ? const Color(0xFF4A3418) : const Color(0xFFFBE7CE),
      onTertiaryContainer:
          dark ? const Color(0xFFF7D9AE) : const Color(0xFF5A3312),

      // Warm-soft: the quieter half of the accent family. Carries the tonal
      // "Done" button and the "plan fits" banner, which want to belong to the
      // amber family without competing with a full-strength CTA.
      secondaryContainer:
          dark ? const Color(0xFF3B2C1C) : const Color(0xFFF7E4CE),
      onSecondaryContainer:
          dark ? const Color(0xFFF3D6B0) : const Color(0xFF4A2E12),
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    // Apply the family over the base text theme *before* our own weight and
    // spacing overrides, so those overrides win. This is what preserves the
    // negative tracking on the large sizes.
    final withFont =
        base.copyWith(textTheme: base.textTheme.apply(fontFamily: fontFamily));

    return withFont.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _text(withFont.textTheme, scheme),

      appBarTheme: AppBarTheme(
        // Centred, bolder, all-caps tracking. The point-size-only header
        // felt undersized; the point-size-plus-tracking version reads as a
        // deliberate mark rather than a default label.
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        titleTextStyle: TextStyle(
          fontFamily: withFont.textTheme.titleLarge?.fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 20,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        toolbarHeight: 60,
      ),

      // Hairline-bordered cards. Elevation and tinted fills both add noise
      // when a dozen of them stack down a list.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        titleTextStyle: base.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: base.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),

      // Primary CTAs are amber. Note this reaches FilledButton.tonal too —
      // one FilledButtonThemeData serves both variants and a theme background
      // beats the tonal default — so the two tonal call sites pass the
      // secondaryContainer pair explicitly to stay the quieter option.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: accentInk,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primary.withValues(alpha: dark ? 0.20 : 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          base.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium
            ?.copyWith(color: scheme.onInverseSurface, height: 1.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        // Translucent when glass is on, so the wrapping GlassSurface in
        // main.dart's sheet builder can blur the layer beneath. Solid when
        // matte, so no accidental transparency where none is intended.
        backgroundColor: material == MaterialChoice.glass
            ? Colors.transparent
            : scheme.surfaceContainerLowest,
        elevation: material == MaterialChoice.glass ? 0 : null,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // The FAB is the one CTA of the screen it appears on, so it joins the
      // amber family rather than sitting in indigo next to an amber button.
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: accentInk,
      ),

      // Amber measures effort: the day's progress here, the overall bar on
      // Progress, and — not by coincidence — the widget's own bar, which has
      // been amber since it shipped. Subject bars pass their own colour and
      // are unaffected.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 6,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }

  /// Negative tracking on the large sizes and a touch of positive tracking on
  /// the small ones. This is most of what separates a considered interface from
  /// a default one, and it costs nothing.
  static TextTheme _text(TextTheme t, ColorScheme scheme) => t.copyWith(
        displaySmall: t.displaySmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -1.0,
          color: scheme.onSurface,
        ),
        headlineSmall: t.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
          color: scheme.onSurface,
        ),
        titleLarge: t.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: scheme.onSurface,
        ),
        titleMedium: t.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        titleSmall: t.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: scheme.onSurface,
        ),
        bodyLarge: t.bodyLarge?.copyWith(height: 1.35, letterSpacing: -0.1),
        bodyMedium: t.bodyMedium?.copyWith(height: 1.45),
        bodySmall: t.bodySmall?.copyWith(
          height: 1.4,
          color: scheme.onSurfaceVariant,
        ),
        labelLarge: t.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        labelSmall: t.labelSmall?.copyWith(letterSpacing: 0.4),
      );
}
