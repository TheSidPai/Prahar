import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  /// Applies [choice] to [base], preserving every weight / size / colour the
  /// theme already assigned. Google Fonts caches on first fetch; if a fetch
  /// fails the platform default renders instead, which is the correct fallback
  /// for a font pick that cannot be resolved.
  static TextTheme fontFor(FontChoice choice, TextTheme base) {
    switch (choice) {
      case FontChoice.system:
        return base;
      case FontChoice.inter:
        return GoogleFonts.interTextTheme(base);
      case FontChoice.manrope:
        return GoogleFonts.manropeTextTheme(base);
      case FontChoice.interTight:
        return GoogleFonts.interTightTextTheme(base);
      case FontChoice.spaceGrotesk:
        return GoogleFonts.spaceGroteskTextTheme(base);
      case FontChoice.fraunces:
        return GoogleFonts.frauncesTextTheme(base);
      case FontChoice.ibmPlexSerif:
        return GoogleFonts.ibmPlexSerifTextTheme(base);
    }
  }

  /// A short label plus a one-line character of each face.
  static (String name, String flavour) describe(FontChoice c) => switch (c) {
        FontChoice.system => ('System', 'Your phone’s own UI font'),
        FontChoice.inter => ('Inter', 'Contemporary, neutral, ubiquitous'),
        FontChoice.manrope => ('Manrope', 'Softer humanist sans'),
        FontChoice.interTight => ('Inter Tight', 'Editorial, close-set'),
        FontChoice.spaceGrotesk => ('Space Grotesk', 'Geometric with quirks'),
        FontChoice.fraunces => ('Fraunces', 'Warm serif with optical care'),
        FontChoice.ibmPlexSerif => ('IBM Plex Serif', 'Editorial serif'),
      };

  static ThemeData of(Brightness brightness, {FontChoice font = FontChoice.inter}) {
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
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    // Apply the font pick over the base text theme *before* our own weight
    // and spacing overrides, so those overrides win. This is what preserves
    // the negative tracking on large sizes across every face.
    final withFont = base.copyWith(textTheme: fontFor(font, base.textTheme));

    return withFont.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _text(withFont.textTheme, scheme),

      appBarTheme: AppBarTheme(
        // Centred and heavier: left-aligned at title size felt undersized and
        // adrift on wide screens. Centred with weight reads as a considered
        // header even at a small point size.
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          fontSize: 15,
          color: scheme.onSurface,
        ),
        toolbarHeight: 52,
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

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
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
        backgroundColor: scheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
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
