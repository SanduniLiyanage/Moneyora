import 'package:flutter/material.dart';

/// Moneyora's semantic colours, as a [ThemeExtension].
///
/// Widgets read these through the theme rather than importing constants:
///
/// ```dart
/// final colors = Theme.of(context).extension<AppColors>()!;
/// Text(amount, style: TextStyle(color: colors.expense));
/// ```
///
/// Going through the theme is what makes light and dark a single switch. A
/// widget that imports a constant directly renders the light value in dark
/// mode, and nothing catches it until someone looks at the screen.
///
/// ## Where these values come from
///
/// The brand is **indigo**, not the green in SRS §4.1. The stakeholder
/// rejected green during requirements gathering because it would read as a
/// copy of Monefy, the reference app, and the instruction did not reach the
/// document. See E-01.
///
/// The semantic trio is unchanged from SRS §4.1: green for money in, red for
/// money out, teal for transfers. That is a cross-cultural finance convention
/// rather than a Monefy trait, and inverting it would cost comprehension for
/// nothing.
///
/// ## Every pair here is measured, not assumed
///
/// E-01 said to verify the 4.5:1 floor rather than trust the table, and doing
/// so caught one failure: teal 600 (`#00897B`) reaches only **4.14:1** on the
/// light surface. It is teal 700 (`#00796B`, 5.10:1) below. The dark values
/// all passed unchanged.
///
/// `app_colors_test.dart` recomputes every ratio on each run, so a future
/// tweak that breaks readability fails CI instead of shipping.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Creates a semantic colour set.
  const AppColors({
    required this.brand,
    required this.onBrand,
    required this.brandContainer,
    required this.accent,
    required this.onAccent,
    required this.income,
    required this.expense,
    required this.transfer,
  });

  /// App bar, primary FAB, and anything AI- or plan-related.
  final Color brand;

  /// Text and icons drawn on top of [brand].
  final Color onBrand;

  /// Selected chips, plan cards — a tinted surface, not a text colour.
  final Color brandContainer;

  /// Highlights, active navigation, progress fill.
  final Color accent;

  /// Text and icons drawn on top of [accent].
  final Color onAccent;

  /// Money in. FR-INC-005.
  final Color income;

  /// Money out. FR-INC-005.
  final Color expense;

  /// Account-to-account movement, which is neither income nor expense.
  /// Distinct precisely so it reads as "not spending" at a glance — see E-02
  /// on why conflating the two inflates both totals.
  final Color transfer;

  /// Light theme. Every pair verified against `#FAFAFA`.
  static const AppColors light = AppColors(
    brand: Color(0xFF3F51B5),
    onBrand: Color(0xFFFFFFFF),
    brandContainer: Color(0xFFE8EAF6),
    accent: Color(0xFFFFB300),
    onAccent: Color(0xFF1C1B1F),
    income: Color(0xFF2E7D32),
    expense: Color(0xFFC62828),
    // Teal 700, not 600: 600 measured 4.14:1 and fails the floor.
    transfer: Color(0xFF00796B),
  );

  /// Dark theme. Chosen for the dark surface, not lightened from the light set.
  static const AppColors dark = AppColors(
    brand: Color(0xFF7986CB),
    onBrand: Color(0xFF1C1B1F),
    brandContainer: Color(0xFF283593),
    accent: Color(0xFFFFCA28),
    onAccent: Color(0xFF1C1B1F),
    income: Color(0xFF66BB6A),
    expense: Color(0xFFEF5350),
    transfer: Color(0xFF4DB6AC),
  );

  /// Page background, light.
  static const Color surfaceLight = Color(0xFFFAFAFA);

  /// Page background, dark.
  static const Color surfaceDark = Color(0xFF121212);

  /// Body text, light.
  static const Color onSurfaceLight = Color(0xFF1C1B1F);

  /// Body text, dark.
  static const Color onSurfaceDark = Color(0xFFE6E1E5);

  @override
  AppColors copyWith({
    Color? brand,
    Color? onBrand,
    Color? brandContainer,
    Color? accent,
    Color? onAccent,
    Color? income,
    Color? expense,
    Color? transfer,
  }) => AppColors(
    brand: brand ?? this.brand,
    onBrand: onBrand ?? this.onBrand,
    brandContainer: brandContainer ?? this.brandContainer,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    income: income ?? this.income,
    expense: expense ?? this.expense,
    transfer: transfer ?? this.transfer,
  );

  /// Interpolates between two sets, so a theme switch animates rather than
  /// snapping.
  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      brandContainer: Color.lerp(brandContainer, other.brandContainer, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
    );
  }
}
