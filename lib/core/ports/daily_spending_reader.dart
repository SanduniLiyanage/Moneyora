import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// What was spent on one day, over every account and category. FR-PLN-006.
///
/// Amounts are integer minor units (E-06).
class DailySpending extends Equatable {
  /// Creates a day's spending.
  const DailySpending({required this.day, required this.amountCents});

  /// The calendar day, at local midnight.
  final DateTime day;

  /// What was spent that day. Always positive: a day with nothing spent has
  /// no row.
  final int amountCents;

  @override
  List<Object?> get props => [day, amountCents];
}

/// Reads expense spending per day from the local database. FR-PLN-006.
///
/// The same seam as `MonthlySpendingReader`'s, cut by day: **analytics**
/// owns the query (the heatmap's), and the **Money Plan Generator** reads
/// it to find when in the week and the month the money goes. Neither
/// feature may import the other (`check_architecture.sh` rule 4).
abstract class DailySpendingReader {
  /// Expense spending per day between [from] and [to], both **inclusive**
  /// whole days, over every account. Sparse: a day with nothing spent has
  /// no row. Transfers are excluded (E-02) and split parts count (E-04).
  Future<Either<Failure, List<DailySpending>>> dailySpending({
    required DateTime from,
    required DateTime to,
  });
}
