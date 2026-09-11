/// The pickable colours for a category. FR-EXP-004.
///
/// These are not a fresh set — they are `default_seed.dart`'s own fifteen
/// expense hues, deduplicated. That file's doc comment explains why the
/// values cannot be chosen by eye: an eyeballed categorical palette was tried
/// first and failed, with colours reading as grey to normal vision and pairs
/// indistinguishable to the ~8% of men with a colour vision deficiency. The
/// set here is the one that was actually validated for that purpose, so a
/// category the user creates fits the same guarantee as one the seed
/// provides, rather than introducing a colour nobody checked.
///
/// [Category.colorHex] stores only the light value, the same convention
/// `applyDefaultSeed` uses — the dark step is resolved at render time from
/// [darkFor], not carried in the database.
library;

import 'package:flutter/material.dart';

/// One pickable swatch: the light value stored, and its dark counterpart.
class CategorySwatch {
  /// Creates a swatch.
  const CategorySwatch({required this.light, required this.dark});

  /// `#RRGGBB`. What is written to `categories.color`.
  final String light;

  /// `#RRGGBB`. Rendered instead of [light] on a dark surface.
  final String dark;
}

/// The validated palette, in `default_seed.dart`'s own order — the order its
/// adjacency check was run against.
const List<CategorySwatch> categoryPalette = [
  CategorySwatch(light: '#2a78d6', dark: '#3987e5'),
  CategorySwatch(light: '#00897b', dark: '#00897b'),
  CategorySwatch(light: '#eb6834', dark: '#d95926'),
  CategorySwatch(light: '#1baf7a', dark: '#199e70'),
  CategorySwatch(light: '#ad1457', dark: '#c2185b'),
  CategorySwatch(light: '#eda100', dark: '#c98500'),
  CategorySwatch(light: '#7b5ea7', dark: '#9085e9'),
  CategorySwatch(light: '#008300', dark: '#008300'),
  CategorySwatch(light: '#e87ba4', dark: '#d55181'),
  CategorySwatch(light: '#7cb342', dark: '#689f38'),
  CategorySwatch(light: '#d81b60', dark: '#d81b60'),
  CategorySwatch(light: '#9e9d24', dark: '#8c8c1f'),
  CategorySwatch(light: '#0097a7', dark: '#0097a7'),
  CategorySwatch(light: '#e34948', dark: '#e66767'),
  CategorySwatch(light: '#9c27b0', dark: '#ab47bc'),
];

/// The default for a category that has not chosen a colour yet.
const String defaultCategoryColorHex = '#2a78d6';

/// Parses `#RRGGBB` into a [Color], or null if [hex] is not that shape.
///
/// Never throws — [hex] can arrive from a restored backup or an older build,
/// same reasoning as `categoryIconFor`.
Color? colorFromHex(String hex) {
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

/// The swatch on screen for [hex], following the current [brightness].
///
/// Falls back to [hex] itself parsed directly when it is not one of
/// [categoryPalette]'s own values — a category recoloured before this picker
/// existed, or restored from a backup, still renders rather than defaulting
/// away from what the user chose.
Color categoryColorFor(String hex, Brightness brightness) {
  for (final swatch in categoryPalette) {
    if (swatch.light == hex) {
      return colorFromHex(
        brightness == Brightness.dark ? swatch.dark : swatch.light,
      )!;
    }
  }
  return colorFromHex(hex) ?? colorFromHex(defaultCategoryColorHex)!;
}
