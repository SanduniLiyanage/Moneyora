/// The built-in icons a category can be given. FR-EXP-004.
///
/// In `core/widgets/` rather than the categories feature, for the same reason
/// `account_icons.dart` sits here: the entry screen's category chips (in
/// `features/transactions/`) need to render the same glyphs, and rule 4 of
/// `check_architecture.sh` forbids one feature importing another. A lookup
/// table with no business logic is exactly what `ARCHITECTURE.md` §5 sends to
/// `core/`.
///
/// The keys below are not invented for this catalogue — they are the icon
/// strings `default_seed.dart` already writes into `categories.icon` for the
/// fifteen expense and three income defaults (`basket`, `receipt`, `car`, and
/// so on). Keeping the same keys means a seeded category and a user-created
/// one render through the same map, rather than two catalogues that can drift
/// apart.
library;

import 'package:flutter/material.dart';

/// One pickable category icon.
class CategoryIcon {
  /// Creates an entry in the catalogue.
  const CategoryIcon({
    required this.key,
    required this.label,
    required this.icon,
  });

  /// What is written to `categories.icon`.
  ///
  /// A stable string, never the enum name or the list position — the same
  /// reasoning as `AccountIcon.key`: reordering this list must not silently
  /// change what an existing category displays.
  final String key;

  /// What the picker announces, and what a screen reader reads.
  final String label;

  /// The glyph itself.
  final IconData icon;
}

/// The catalogue. The first eighteen are `default_seed.dart`'s own keys, in
/// its seed order, so the default categories are the first things a user sees
/// when they open the picker to change one. The rest extend coverage for
/// FR-EXP-004's custom categories.
const List<CategoryIcon> categoryIcons = [
  CategoryIcon(key: 'receipt', label: 'Bills', icon: Icons.receipt_long),
  CategoryIcon(key: 'car', label: 'Car', icon: Icons.directions_car),
  CategoryIcon(key: 'tshirt', label: 'Clothes', icon: Icons.checkroom),
  CategoryIcon(key: 'phone', label: 'Communications', icon: Icons.phone),
  CategoryIcon(key: 'cutlery', label: 'Eating out', icon: Icons.restaurant),
  CategoryIcon(key: 'cocktail', label: 'Entertainment', icon: Icons.local_bar),
  CategoryIcon(key: 'basket', label: 'Food', icon: Icons.shopping_basket),
  CategoryIcon(key: 'gift', label: 'Gifts', icon: Icons.card_giftcard),
  CategoryIcon(key: 'thermometer', label: 'Health', icon: Icons.thermostat),
  CategoryIcon(key: 'home', label: 'House', icon: Icons.home),
  CategoryIcon(key: 'cat', label: 'Pets', icon: Icons.pets),
  CategoryIcon(key: 'runner', label: 'Sports', icon: Icons.directions_run),
  CategoryIcon(key: 'taxi', label: 'Taxi', icon: Icons.local_taxi),
  CategoryIcon(key: 'toothbrush', label: 'Toiletry', icon: Icons.clean_hands),
  CategoryIcon(key: 'train', label: 'Transport', icon: Icons.train),
  CategoryIcon(key: 'money-bag', label: 'Deposits', icon: Icons.savings),
  CategoryIcon(key: 'coins', label: 'Salary', icon: Icons.payments),
  CategoryIcon(
    key: 'piggy-bank',
    label: 'Savings',
    icon: Icons.account_balance_wallet,
  ),
  CategoryIcon(key: 'book', label: 'Education', icon: Icons.menu_book),
  CategoryIcon(key: 'briefcase', label: 'Work', icon: Icons.work_outline),
  CategoryIcon(key: 'plane', label: 'Travel', icon: Icons.flight),
  CategoryIcon(key: 'tools', label: 'Repairs', icon: Icons.build),
  CategoryIcon(key: 'game', label: 'Hobbies', icon: Icons.sports_esports),
  CategoryIcon(key: 'baby', label: 'Kids', icon: Icons.child_care),
  CategoryIcon(key: 'heart', label: 'Charity', icon: Icons.favorite_border),
  CategoryIcon(key: 'movie', label: 'Movies', icon: Icons.movie_outlined),
  CategoryIcon(key: 'coffee', label: 'Coffee', icon: Icons.local_cafe),
  CategoryIcon(key: 'investment', label: 'Investment', icon: Icons.trending_up),
  CategoryIcon(key: 'other', label: 'Other', icon: Icons.category_outlined),
];

/// The default for a new category that has not picked one yet.
const String defaultCategoryIconKey = 'other';

/// The glyph for [key], or the default when nothing matches.
///
/// Never throws — the same reasoning as `accountIconFor`: an unknown key is
/// not a programming error but a restored backup, a row from an older build,
/// or a future release that retires an icon, and a crash is a much worse
/// answer than a generic category glyph.
IconData categoryIconFor(String key) {
  for (final entry in categoryIcons) {
    if (entry.key == key) return entry.icon;
  }
  return Icons.category_outlined;
}
