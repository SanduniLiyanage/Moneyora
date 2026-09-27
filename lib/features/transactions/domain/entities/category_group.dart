import 'package:equatable/equatable.dart';

import 'transaction.dart';

/// One transaction's place in a [CategoryGroup].
class CategoryGroupEntry extends Equatable {
  /// Creates an entry.
  const CategoryGroupEntry({
    required this.transaction,
    required this.amountCents,
  });

  /// The row itself, whole, so tapping it edits all of it.
  final Transaction transaction;

  /// What this group holds of it: the whole amount, or one split part's.
  final int amountCents;

  @override
  List<Object?> get props => [transaction, amountCents];
}

/// The transactions filed under one category. FR-EXP-011, E-11.
///
/// The list's second mode reads the same filtered rows as the chronological
/// one, so this is a pure regrouping of them, not a query: the two modes
/// cannot disagree about what was recorded.
class CategoryGroup extends Equatable {
  /// Creates a group.
  const CategoryGroup({required this.categoryId, required this.entries});

  /// The category, or null for the transfers group, which has none (E-17).
  final int? categoryId;

  /// Newest first, in the order the list was given them.
  final List<CategoryGroupEntry> entries;

  /// True for the one group that holds transfers.
  bool get isTransfers => categoryId == null;

  /// E-11's count badge.
  int get count => entries.length;

  /// Income in minus spending out, in minor units.
  ///
  /// Signed rather than a bare sum so a category that somehow holds both
  /// kinds still shows what it did to the balance. Zero for transfers: a
  /// transfer moves money between the user's own accounts, and a total of
  /// them would count it as spending or income (E-02).
  int get netCents => entries.fold(0, (sum, entry) {
    return switch (entry.transaction.type) {
      TransactionType.income => sum + entry.amountCents,
      TransactionType.expense => sum - entry.amountCents,
      TransactionType.transfer => sum,
    };
  });

  /// Groups [transactions] by category, largest total first.
  ///
  /// A split sits in each of its parts' categories with that part's amount,
  /// so every group's total is what was actually spent there (E-04) and a
  /// part filed in the wrong place can be found under the category it is
  /// in. Such a row counts once in each group it appears in.
  ///
  /// Ties go to the busier group, then the lower id, so the order is stable
  /// as rows stream in. Transfers come last, whatever they add up to.
  static List<CategoryGroup> group(Iterable<Transaction> transactions) {
    final byCategory = <int?, List<CategoryGroupEntry>>{};

    void add(int? categoryId, Transaction transaction, int amountCents) =>
        (byCategory[categoryId] ??= []).add(
          CategoryGroupEntry(
            transaction: transaction,
            amountCents: amountCents,
          ),
        );

    for (final transaction in transactions) {
      if (transaction.type == TransactionType.transfer) {
        add(null, transaction, transaction.amountCents);
      } else if (transaction.isSplit) {
        // Two parts in one category are one entry holding both.
        final parts = <int, int>{};
        for (final split in transaction.splits) {
          parts[split.categoryId] =
              (parts[split.categoryId] ?? 0) + split.amountCents;
        }
        parts.forEach((id, cents) => add(id, transaction, cents));
      } else {
        add(transaction.categoryId, transaction, transaction.amountCents);
      }
    }

    final groups = [
      for (final MapEntry(:key, :value) in byCategory.entries)
        CategoryGroup(categoryId: key, entries: List.unmodifiable(value)),
    ];
    groups.sort((a, b) {
      if (a.isTransfers != b.isTransfers) return a.isTransfers ? 1 : -1;
      final byTotal = b.netCents.abs().compareTo(a.netCents.abs());
      if (byTotal != 0) return byTotal;
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return (a.categoryId ?? 0).compareTo(b.categoryId ?? 0);
    });
    return groups;
  }

  @override
  List<Object?> get props => [categoryId, entries];
}
