import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/category_total.dart';

/// A closed period to report over, both ends **inclusive** whole days.
///
/// Inclusive at both ends because that is how a person says it — "the first to
/// the thirty-first of August" — and an exclusive end silently drops the last
/// day's spending, which is a wrong answer that looks plausible.
class DateRange extends Equatable {
  /// Creates a range from [from] to [to], inclusive.
  const DateRange({required this.from, required this.to});

  /// The whole of one calendar month.
  ///
  /// Here rather than at each call site because the last day of a month is
  /// `DateTime(year, month + 1, 0)` — correct, and unmemorable enough that
  /// every rediscovery of it is a chance to write `30` and be wrong four times
  /// a year.
  factory DateRange.month(int year, int month) =>
      DateRange(from: DateTime(year, month), to: DateTime(year, month + 1, 0));

  /// First day of the period.
  final DateTime from;

  /// Last day of the period.
  final DateTime to;

  /// True when the range runs backwards.
  bool get isInverted => from.isAfter(to);

  @override
  List<Object?> get props => [from, to];
}

/// Reads over transaction history. No writes: analytics never changes a row.
abstract class AnalyticsRepository {
  /// Totals expense spending per category over [range], largest first.
  ///
  /// Transfers are excluded (E-02) and split parts are counted against their
  /// own categories rather than the parent's (E-04).
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    DateRange range,
  );

  /// Totals income over [range]. FR-COP-008.
  ///
  /// Income is never split (E-04's split table exists for FR-EXP-010's
  /// expenses only), so this is a plain sum with no union to write.
  Future<Either<Failure, int>> incomeForPeriod(DateRange range);
}
