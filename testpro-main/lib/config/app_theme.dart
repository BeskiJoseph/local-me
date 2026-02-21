import 'package:flutter/material.dart';

/// ============================================================
/// APP THEME — Design System v2
/// Primary: #2F7D6A (Forest Green)
/// Font: Inter
/// ============================================================
class AppTheme {
  AppTheme._();

  // ── Brand Colors ─────────────────────────────────────────
  static const Color primary        = Color(0xFF2F7D6A);
  static const Color primaryLight   = Color(0xFFE6F2EE);
  static const Color primaryDark    = Color(0xFF1F5C4E);

  // ── Neutral / Background ──────────────────────────────────
  static const Color background     = Color(0xFFF7F8FA);
  static const Color cardWhite      = Color(0xFFFFFFFF);
  static const Color border         = Color(0xFFECECEC);

  // ── Text ─────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFF1A1A1A);
  static const Color textSecondary  = Color(0xFF6E6E73);
  static const Color textMuted      = Color(0xFF9E9E9E);

  // ── Semantic ──────────────────────────────────────────────
  static const Color likeActive     = Color(0xFFE53935);
  static const Color verified       = Color(0xFF2F7D6A);
  static const Color badgeRed       = Color(0xFFE53935);

  // ── Legacy aliases (keep existing code compiling) ─────────
  static const Color deepPurple          = primary;
  static const Color electricBlue        = primary;
  static const Color vibrantCyan         = primaryLight;
  static const Color neonPink            = Color(0xFFFF6B9D);
  static const Color sunsetOrange        = Color(0xFFFF7675);
  static const Color limeGreen           = primary;
  static const Color royalPurple         = primary;
  static const Color skyBlue             = primary;
  static const Color lightBackground     = background;
  static const Color lightSurface        = cardWhite;
  static const Color lightCard           = cardWhite;
  static const Color lightText           = textPrimary;
  static const Color lightTextSecondary  = textSecondary;
  static const Color lightBorder         = border;
  static const Color darkBackground      = Color(0xFF0F0F0F);
  static const Color darkSurface         = Color(0xFF1A1A1A);
  static const Color darkCard            = Color(0xFF252525);
  static const Color darkText            = Color(0xFFFAFAFA);
  static const Color darkTextSecondary   = Color(0xFF9CA3AF);
  static const Color darkBorder          = Color(0xFF2D2D2D);
  static const Color primaryBlue         = primary;
  static const Color primaryText         = textPrimary;
  static const Color secondaryText       = textSecondary;
  static const Color mutedText           = textMuted;
  static const Color dividerBorder       = border;
  static const Color activeIcon          = primary;
  static const Color inactiveIcon        = textSecondary;
  static const Color eventGreen          = primary;
  static const Color eventOrange         = Color(0xFFFF6B6B);

  // ── Typography Presets ────────────────────────────────────
  static const String fontFamily = 'Inter';

  static const TextStyle postUsername = TextStyle(
    fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary,
  );
  static const TextStyle postMeta = TextStyle(
    fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w400, color: textSecondary,
  );
  static const TextStyle postContent = TextStyle(
    fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w400, height: 1.5, color: textPrimary,
  );
  static const TextStyle actionCount = TextStyle(
    fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF3A3A3C),
  );
  static const TextStyle tabActive = TextStyle(
    fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600,
  );
  static const TextStyle tabInactive = TextStyle(
    fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w500,
  );

  // ── Spacing ───────────────────────────────────────────────
  static const double spacing4  = 4.0;
  static const double spacing8  = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing48 = 48.0;

  // ── Border Radius ─────────────────────────────────────────
  static const double radiusSmall  = 12.0;
  static const double radiusMedium = 16.0;
  static const double radiusLarge  = 24.0;
  static const double radiusXLarge = 28.0;
  static const double radiusCircle = 999.0;

  // ── Animation ─────────────────────────────────────────────
  static const Duration durationFast   = Duration(milliseconds: 200);
  static const Duration durationNormal = Duration(milliseconds: 350);
  static const Duration durationSlow   = Duration(milliseconds: 500);

  // ── Shadows ───────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => [
    BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4)),
  ];
  static List<BoxShadow> get glowShadow => [
    BoxShadow(color: primary.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8)),
  ];

  // ── Gradients (kept for legacy) ───────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFFF6B9D), Color(0xFFFF7675)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const LinearGradient successGradient = LinearGradient(
    colors: [primary, primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const LinearGradient shimmerGradient = LinearGradient(
    colors: [Color(0xFFEBEBF4), Color(0xFFF4F4F4), Color(0xFFEBEBF4)],
    stops: [0.1, 0.3, 0.4],
    begin: Alignment(-1.0, -0.3), end: Alignment(1.0, 0.3),
  );

  // ── Light Theme ───────────────────────────────────────────
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primary,
    scaffoldBackgroundColor: background,

    colorScheme: const ColorScheme.light(
      primary: primary,
      secondary: primaryLight,
      surface: cardWhite,
      background: background,
      error: Color(0xFFE53935),
      onPrimary: Colors.white,
      onSecondary: textPrimary,
      onSurface: textPrimary,
      onBackground: textPrimary,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: cardWhite,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        color: textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: cardWhite,
      selectedItemColor: primary,
      unselectedItemColor: textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      showSelectedLabels: true,
      showUnselectedLabels: true,
    ),

    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontFamily: fontFamily, fontSize: 36, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -1),
      displayMedium: TextStyle(fontFamily: fontFamily, fontSize: 32, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.8),
      displaySmall:  TextStyle(fontFamily: fontFamily, fontSize: 28, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.6),
      headlineLarge: TextStyle(fontFamily: fontFamily, fontSize: 24, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.5),
      headlineMedium:TextStyle(fontFamily: fontFamily, fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: -0.3),
      headlineSmall: TextStyle(fontFamily: fontFamily, fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
      titleLarge:    TextStyle(fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
      titleMedium:   TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
      titleSmall:    TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
      bodyLarge:     TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w400, color: textPrimary, height: 1.5),
      bodyMedium:    TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary, height: 1.5),
      bodySmall:     TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w400, color: textSecondary, height: 1.4),
      labelLarge:    TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
      labelMedium:   TextStyle(fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w500, color: textSecondary),
      labelSmall:    TextStyle(fontFamily: fontFamily, fontSize: 11, fontWeight: FontWeight.w500, color: textMuted),
    ),

    cardTheme: CardThemeData(
      color: cardWhite,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        side: const BorderSide(color: border, width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing8),
    ),

    dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),

    chipTheme: ChipThemeData(
      backgroundColor: primaryLight,
      labelStyle: const TextStyle(
        fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w600, color: primary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide.none,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing16),
      hintStyle: const TextStyle(fontFamily: fontFamily, color: textMuted, fontSize: 14),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLarge)),
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLarge)),
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing12),
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCircle)),
    ),
  );

  // ── Dark Theme (unchanged structure, updated colors) ──────
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primary,
    scaffoldBackgroundColor: darkBackground,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: primaryLight,
      surface: darkSurface,
      background: darkBackground,
      error: Color(0xFFE53935),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: darkText,
      onBackground: darkText,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBackground,
      foregroundColor: darkText,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );

  // ── Helpers ───────────────────────────────────────────────
  static BoxDecoration gradientDecoration({Gradient? gradient, double borderRadius = radiusMedium}) {
    return BoxDecoration(
      gradient: gradient ?? primaryGradient,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: glowShadow,
    );
  }

  static BoxDecoration glassDecoration({Color? color, double borderRadius = radiusMedium, double blur = 10}) {
    return BoxDecoration(
      color: (color ?? Colors.white).withOpacity(0.1),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: blur, offset: const Offset(0, 4))],
    );
  }
}
