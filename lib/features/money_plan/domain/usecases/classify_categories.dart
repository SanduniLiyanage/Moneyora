import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/category_classification.dart';
import '../entities/category_statistics.dart';
import '../entities/lookback_window.dart';
import 'compute_category_statistics.dart';

/// Fixed / Variable / Seasonal, per category, over a lookback window.
/// FR-PLN-004, E-07.
///
/// The second stage of the plan generator: [ComputeCategoryStatistics]
/// describes each category, this decides what kind of cost it is. Pure
/// arithmetic over those statistics (E-05); no query of its own.
///
/// Seasonal is tested first, then Fixed, then Variable as the fallback —
/// the specific finding before the general one. In practice the order
/// cannot change a verdict: two months that each clear 1.5x the mean put
/// the CV of 24 months at about 0.16 or more, so a seasonal category is
/// never under the Fixed line anyway.
///
/// This stage says what a category *is*, not how far to trust it. A category
/// with three rows in two years is classified from those three rows;
/// FR-PLN-010's confidence score is where "too little data" is decided.
class ClassifyCategories
    implements UseCase<List<CategoryClassification>, LookbackWindow> {
  /// Creates the use case over the statistics stage.
  const ClassifyCategories(this._statistics);

  final ComputeCategoryStatistics _statistics;

  /// Below this coefficient of variation a category is Fixed — the SDD's
  /// own threshold, applied to monthly totals.
  ///
  /// Kept as specified rather than widened for the smoothing monthly
  /// totals do: Fixed means "budget the exact recent average" (FR-PLN-007),
  /// and a category whose monthly total holds within 15% is one where that
  /// is safe however many transactions make it up. Near the line the Fixed
  /// and Variable allocations converge anyway, so a borderline call costs
  /// little either way — and that is an argument for not moving the line
  /// to suit one fixture. The seed's Food lands at 0.157: Variable.
  static const double fixedCvCeiling = 0.15;

  /// A month whose total exceeds this multiple of the mean is a spike.
  static const double seasonalIndex = 1.5;

  @override
  Future<Either<Failure, List<CategoryClassification>>> call(
    LookbackWindow params,
  ) async {
    final statistics = await _statistics(params);
    return statistics.map((all) => [for (final s in all) classify(s, params)]);
  }

  /// One category's class, from its statistics over [window].
  ///
  /// Static so a test can state the rules without a reader beneath them.
  static CategoryClassification classify(
    CategoryStatistics statistics,
    LookbackWindow window,
  ) {
    final seasonalMonths = seasonalMonthsOf(statistics, window);
    if (seasonalMonths.isNotEmpty) {
      return CategoryClassification(
        statistics: statistics,
        type: ExpenseType.seasonal,
        seasonalMonths: seasonalMonths,
      );
    }
    return CategoryClassification(
      statistics: statistics,
      type: statistics.coefficientOfVariation < fixedCvCeiling
          ? ExpenseType.fixed
          : ExpenseType.variable,
    );
  }

  /// The calendar months (1–12) in which [statistics] spikes every year the
  /// window holds, ascending. Empty when there are none — or when the
  /// window is shorter than E-07's 24 months, whatever the totals say.
  ///
  /// E-07's month-of-year index is `mean(month) / mean(all months)`, flagged
  /// above [seasonalIndex] when it *recurs* across at least two years. Read
  /// strictly: every occurrence of the month must clear the index on its
  /// own, so one enormous December and one ordinary one do not average into
  /// a cycle. Over 24 whole months every calendar month occurs exactly
  /// twice, which is the two years the rule asks for.
  static List<int> seasonalMonthsOf(
    CategoryStatistics statistics,
    LookbackWindow window,
  ) {
    if (window.months < LookbackWindow.maxMonths ||
        statistics.monthCount != window.months ||
        statistics.meanCents <= 0) {
      return const [];
    }

    final starts = window.monthStarts;
    final byCalendarMonth = <int, List<int>>{};
    for (var i = 0; i < starts.length; i++) {
      byCalendarMonth
          .putIfAbsent(starts[i].month, () => [])
          .add(statistics.monthlyTotalsCents[i]);
    }

    final threshold = seasonalIndex * statistics.meanCents;
    return [
      for (final MapEntry(key: month, value: totals) in byCalendarMonth.entries)
        if (totals.length >= 2 && totals.every((t) => t > threshold)) month,
    ]..sort();
  }
}
