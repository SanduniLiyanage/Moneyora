/// The categories and accounts an entry screen has to offer.
///
/// ## Why this is in `core/database/` and not a feature
///
/// Categories and accounts are not owned by transactions. Analytics groups by
/// category, the Money Plan allocates to categories, and the receipt scanner
/// classifies into them; accounts are the subject of Sprint 3 outright. So a
/// `features/categories/` slice imported by `features/transactions/` would
/// break the no-cross-feature-imports rule the moment it was written, and
/// `lib/core/` is where this guide already sends anything two features share.
///
/// It follows the shape of `database_summary.dart` deliberately: a read that
/// holds its own SQL, in one of the two directories where SQL is permitted.
///
/// **This is an interim home.** When FR-EXP-003 to FR-EXP-005 land — creating,
/// renaming and nesting categories — categories earn a proper slice with
/// entities, a repository and use cases, and the entry screen's inline `+`
/// (E-13) belongs to that work. Reading a seeded list does not justify the
/// ceremony yet; editing one will.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

/// One pickable category. FR-EXP-003.
class CategoryOption {
  /// Creates a category option.
  const CategoryOption({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.isExpense,
  });

  /// Row id, used as `transactions.category_id`.
  final int id;

  /// What the chip reads.
  final String name;

  /// Icon key from the seed, e.g. `basket`.
  final String icon;

  /// `#RRGGBB` from the seed, used for the chip and later the donut chart.
  final String colorHex;

  /// True for spending categories, false for income ones.
  ///
  /// The entry screen shows one set or the other, never both: an expense
  /// filed under Salary is not a mistake worth allowing.
  final bool isExpense;
}

/// One account money can sit in. FR-ACC-001.
class AccountOption {
  /// Creates an account option.
  const AccountOption({
    required this.id,
    required this.name,
    required this.balanceCents,
  });

  /// Row id, used as `transactions.account_id`.
  final int id;

  /// What the user calls it — Cash, Payment card.
  final String name;

  /// The cached balance (E-18), for display only.
  final int balanceCents;
}

/// Everything an entry screen needs to render its pickers.
class EntryCatalog {
  /// Creates a catalog.
  const EntryCatalog({required this.categories, required this.accounts});

  /// Every category, both kinds, in seed order.
  final List<CategoryOption> categories;

  /// Every account that is not archived.
  final List<AccountOption> accounts;

  /// Spending categories, in the order the seed defines.
  List<CategoryOption> get expenseCategories =>
      categories.where((c) => c.isExpense).toList();

  /// Income categories.
  List<CategoryOption> get incomeCategories =>
      categories.where((c) => !c.isExpense).toList();
}

/// Reads the catalog from [db].
Future<EntryCatalog> readEntryCatalog(Database db) async {
  final categoryRows = await db.query(
    'categories',
    // Seed order, then name, so the list a user sees does not reshuffle
    // itself between launches for no reason they can perceive.
    orderBy: 'sort_order ASC, name ASC',
  );

  final accountRows = await db.query(
    'accounts',
    where: 'is_archived = 0',
    orderBy: 'id ASC',
  );

  return EntryCatalog(
    categories: [
      for (final row in categoryRows)
        CategoryOption(
          id: row['id']! as int,
          name: row['name']! as String,
          icon: row['icon']! as String,
          colorHex: row['color']! as String,
          isExpense: row['type'] == 'expense',
        ),
    ],
    accounts: [
      for (final row in accountRows)
        AccountOption(
          id: row['id']! as int,
          name: row['name']! as String,
          balanceCents: row['current_balance_cents']! as int,
        ),
    ],
  );
}
