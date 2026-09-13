import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/analytics_query.dart';
import '../entities/daily_total.dart';
import '../entities/spending_calendar.dart';
import '../repositories/analytics_repository.dart';

/// One month of daily spending totals, for one account or all of them.
/// FR-RPT-009, FR-RPT-003.
///
/// The query beneath the calendar heatmap. Takes a month rather than an
/// [AnalyticsQuery] because the heatmap always draws a calendar month — the
/// parameter type is where that decision lives, so a caller cannot ask it for
/// a year. The account filter reaches it for the reason it reached the bars
/// and the lines: a card under the filter row that ignored the account would
/// look filtered and not be.
///
/// Over [AnalyticsRepository.dailySpendingTotals] rather than `spendingTrend`
/// at day granularity folded per day: measured on the 10,000-row benchmark
/// fixture (`analytics_query_benchmark_test.dart`), the one-row-per-day
/// statement with no `categories` join is the cheaper of the two, and it
/// returns at most 31 rows instead of up to 31 × categories.
class GetSpendingCalendar
    implements UseCase<SpendingCalendar, SpendingCalendarQuery> {
  /// Creates the use case.
  const GetSpendingCalendar(this._repository);

  final AnalyticsRepository _repository;

  @override
  Future<Either<Failure, SpendingCalendar>> call(
    SpendingCalendarQuery params,
  ) async {
    final range = DateRange.month(params.year, params.month);
    final totals = await _repository.dailySpendingTotals(
      AnalyticsQuery(range: range, accountId: params.accountId),
    );
    return totals.map(
      (sparse) => SpendingCalendar(
        year: params.year,
        month: params.month,
        amountsCents: _densify(sparse, params.year, params.month, range.to.day),
      ),
    );
  }

  /// One amount per day of the month, zero where nothing was spent. A row
  /// outside the month can only come from a repository answering a different
  /// question than it was asked, and is dropped.
  static List<int> _densify(
    List<DailyTotal> totals,
    int year,
    int month,
    int dayCount,
  ) {
    final amounts = List.filled(dayCount, 0);
    for (final total in totals) {
      if (total.date.year != year || total.date.month != month) continue;
      amounts[total.date.day - 1] += total.amountCents;
    }
    return List.unmodifiable(amounts);
  }
}
