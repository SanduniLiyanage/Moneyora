import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds the light and dark [ThemeData] the app runs on.
///
/// FR-SET-001 (light and dark with a user toggle) and SRS §4.1 (Material
/// Design 3, 48dp touch targets, system font scaling).
abstract final class AppTheme {
  /// Minimum interactive size, SRS §4.1.
  ///
  /// Material's own default is 48dp already, but it is set explicitly because
  /// a custom keypad (FR-EXP-002) is built from bare `InkWell`s that inherit
  /// nothing, and an undersized key is the kind of thing that only shows up
  /// when someone with larger hands tries the app.
  static const double minTouchTarget = 48;

  /// Light theme.
  static ThemeData get light => _build(
    brightness: Brightness.light,
    colors: AppColors.light,
    surface: AppColors.surfaceLight,
    onSurface: AppColors.onSurfaceLight,
  );

  /// Dark theme.
  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    colors: AppColors.dark,
    surface: AppColors.surfaceDark,
    onSurface: AppColors.onSurfaceDark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required AppColors colors,
    required Color surface,
    required Color onSurface,
  }) {
    // The scheme is written out rather than generated with
    // ColorScheme.fromSeed. Seeding derives a whole tonal palette from one
    // colour, which is excellent when you have no opinion — but every value
    // here was chosen and contrast-verified, and seeding would quietly
    // replace them with harmonised approximations.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.brand,
      onPrimary: colors.onBrand,
      primaryContainer: colors.brandContainer,
      onPrimaryContainer: brightness == Brightness.light
          ? colors.brand
          : Colors.white,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      // Material treats `error` as its own role. Pointing it at the expense
      // red keeps one red in the app: a validation error and an overspent
      // category should not be two different reds.
      error: colors.expense,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      extensions: <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.brand,
        foregroundColor: colors.onBrand,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.brand,
        foregroundColor: colors.onBrand,
      ),
      // 48dp floors on everything Material sizes for us.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
        ),
      ),
      // No fixed font sizes anywhere in the theme: SRS §4.1 requires system
      // font scaling, and hard-coding sizes is what breaks it.
      cardTheme: CardThemeData(
        elevation: 0,
        color: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: onSurface.withValues(alpha: 0.12),
        space: 1,
        thickness: 1,
      ),
    );
  }
}
