import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/theme/app_colors.dart';
import 'package:moneyora/core/theme/app_theme.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio, 1:1 to 21:1.
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  /// SRS §4.1 sets the floor at 4.5:1.
  const floor = 4.5;

  group('contrast — SRS §4.1 requires 4.5:1', () {
    // These are recomputed on every run rather than checked once by hand.
    // A palette tweak that makes an amount unreadable is invisible in a diff
    // and obvious only to whoever cannot read it, which is the worst possible
    // way to find out. Verifying caught teal 600 at 4.14:1 during authoring.

    test('light: every semantic colour is readable on the light surface', () {
      const surface = AppColors.surfaceLight;
      const c = AppColors.light;

      for (final (name, color) in <(String, Color)>[
        ('body text', AppColors.onSurfaceLight),
        ('income', c.income),
        ('expense', c.expense),
        ('transfer', c.transfer),
        ('brand', c.brand),
      ]) {
        final ratio = contrastRatio(color, surface);
        expect(
          ratio,
          greaterThanOrEqualTo(floor),
          reason: '$name is ${ratio.toStringAsFixed(2)}:1 on the light surface',
        );
      }
    });

    test('dark: every semantic colour is readable on the dark surface', () {
      const surface = AppColors.surfaceDark;
      const c = AppColors.dark;

      for (final (name, color) in <(String, Color)>[
        ('body text', AppColors.onSurfaceDark),
        ('income', c.income),
        ('expense', c.expense),
        ('transfer', c.transfer),
        ('brand', c.brand),
      ]) {
        final ratio = contrastRatio(color, surface);
        expect(
          ratio,
          greaterThanOrEqualTo(floor),
          reason: '$name is ${ratio.toStringAsFixed(2)}:1 on the dark surface',
        );
      }
    });

    test('text on brand and accent surfaces is readable', () {
      // These two are backgrounds, not text colours, so the pair that matters
      // is what gets drawn on top of them.
      for (final (name, fg, bg) in <(String, Color, Color)>[
        (
          'onBrand / brand (light)',
          AppColors.light.onBrand,
          AppColors.light.brand,
        ),
        (
          'onAccent / accent (light)',
          AppColors.light.onAccent,
          AppColors.light.accent,
        ),
        (
          'onBrand / brand (dark)',
          AppColors.dark.onBrand,
          AppColors.dark.brand,
        ),
        (
          'onAccent / accent (dark)',
          AppColors.dark.onAccent,
          AppColors.dark.accent,
        ),
      ]) {
        final ratio = contrastRatio(fg, bg);
        expect(
          ratio,
          greaterThanOrEqualTo(floor),
          reason: '$name is ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('semantics', () {
    test('income, expense and transfer are three distinct colours', () {
      // FR-INC-005 requires income and expense to be visually distinguished.
      // Transfers join them because conflating a transfer with spending
      // inflates both totals — see E-02.
      for (final c in [AppColors.light, AppColors.dark]) {
        expect({c.income, c.expense, c.transfer}, hasLength(3));
      }
    });

    test('the brand is not green (E-01)', () {
      // The stakeholder rejected green branding as too close to the reference
      // app. This test is the only thing that would notice a well-meaning
      // revert to the SRS §4.1 wording.
      for (final c in [AppColors.light, AppColors.dark]) {
        final hsl = HSLColor.fromColor(c.brand);
        expect(
          hsl.hue,
          isNot(inInclusiveRange(80, 160)),
          reason: 'brand hue ${hsl.hue.round()}° falls in the green band',
        );
      }
    });
  });

  group('ThemeData', () {
    test('both themes expose AppColors as an extension', () {
      // If the extension is missing, every widget calling
      // Theme.of(context).extension<AppColors>()! crashes at runtime.
      expect(AppTheme.light.extension<AppColors>(), AppColors.light);
      expect(AppTheme.dark.extension<AppColors>(), AppColors.dark);
    });

    test('uses Material 3 and the right brightness', () {
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });

    test('error maps to the expense red, so the app has only one red', () {
      expect(AppTheme.light.colorScheme.error, AppColors.light.expense);
      expect(AppTheme.dark.colorScheme.error, AppColors.dark.expense);
    });

    test('buttons meet the 48dp touch target from SRS §4.1', () {
      final style = AppTheme.light.filledButtonTheme.style!;
      final size = style.minimumSize?.resolve({});
      expect(size!.height, greaterThanOrEqualTo(AppTheme.minTouchTarget));
      expect(size.width, greaterThanOrEqualTo(AppTheme.minTouchTarget));
    });
  });

  group('rendering', () {
    testWidgets('a widget can read semantic colours through the theme', (
      tester,
    ) async {
      late AppColors resolved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              resolved = Theme.of(context).extension<AppColors>()!;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.income, AppColors.light.income);
    });

    testWidgets('switching to dark swaps the palette', (tester) async {
      late AppColors resolved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: Builder(
            builder: (context) {
              resolved = Theme.of(context).extension<AppColors>()!;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.expense, AppColors.dark.expense);
      expect(resolved.expense, isNot(AppColors.light.expense));
    });
  });
}
