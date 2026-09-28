import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// What was spent in one category on one day, over every account.
/// FR-PLN-006.
///
/// Amounts are integer minor units (E-06).
class DailySpending extends Equatable {
  /// Creates a day's spending in one category.
  const DailySpending({
    required this.day,
    required this.categoryId,
    required this.amountCents,
  });

  /// The calendar day, at local midnight.
  final DateTime day;

  /// The category it was spent in — the same id `MonthlySpendingReader`
  /// gives it, so a category the plan classified can be recognised here.
  final int categoryId;

  /// What was spent that day in that category. Always positive: a day with
  /// nothing spent has no row.
  final int amountCents;

  @override
  List<Object?> get props => [day, categoryId, amountCents];
}

/// Reads expense spending per day and category from the local database.
/// FR-PLN-006.
///
/// The same seam as `MonthlySpendingReader`'s, cut by day: **analytics**
/// owns the query (the trend lines'), and the **Money Plan Generator** reads
/// it to find when in the week and the month the money goes. Neither
/// feature may import the other (`check_architecture.sh` rule 4).
abstract class DailySpendingReader {
  /// Expense spending per day and category between [from] and [to], both
  /// **inclusive** whole days, over every account. Sparse: a day and
  /// category with nothing spent has no row. Transfers are excluded (E-02)
  /// and split parts count (E-04).
  Future<Either<Failure, List<DailySpending>>> dailySpending({
    required DateTime from,
    required DateTime to,
  });
}
