import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// One category's expense spending in one calendar month. FR-PLN-005.
///
/// Amounts are integer minor units (E-06).
class MonthlySpending extends Equatable {
  /// Creates a month of spending for one category.
  const MonthlySpending({
    required this.categoryId,
    required this.name,
    required this.month,
    required this.amountCents,
    required this.transactionCount,
  });

  /// The category, as `transactions.category_id`.
  final int categoryId;

  /// The category's display name, e.g. `Food`.
  final String name;

  /// The first day of the month, at local midnight.
  final DateTime month;

  /// What was spent in the month. Always positive: a month with nothing
  /// spent has no row.
  final int amountCents;

  /// How many expense rows (or split parts, E-04) made up [amountCents].
  final int transactionCount;

  @override
  List<Object?> get props => [
    categoryId,
    name,
    month,
    amountCents,
    transactionCount,
  ];
}

/// Reads expense spending per category per month from the local database.
///
/// Lives in `core/` for the same reason [SpendingByCategoryReader] does:
/// **analytics** owns the bucketed query and implements this, and the
/// **Money Plan Generator** consumes it to compute its statistics (E-05 —
/// rows out of SQL, arithmetic in Dart), and neither feature may import the
/// other (`check_architecture.sh` rule 4).
///
/// Unlike that port this one keeps category ids, because a plan stores its
/// allocations against `plan_allocations.category_id` and nothing here is
/// sent off-device.
abstract class MonthlySpendingReader {
  /// Expense spending per category per calendar month between [from] and
  /// [to], both **inclusive** whole days, over every account. Sparse: a
  /// category with nothing spent in a month has no row for it.
  ///
  /// Transfers are excluded (E-02) and split parts count against their own
  /// categories (E-04) — the same rows every analytics aggregate counts.
  Future<Either<Failure, List<MonthlySpending>>> monthlySpendingByCategory({
    required DateTime from,
    required DateTime to,
  });
}
