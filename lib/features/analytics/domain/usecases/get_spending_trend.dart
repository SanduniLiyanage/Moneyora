import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/analytics_query.dart';
import '../entities/spending_trend.dart';
import '../entities/trend_point.dart';
import '../repositories/analytics_repository.dart';
import 'get_spending_by_category.dart';

/// Per-category spending over time, for one account or all of them.
/// FR-RPT-005, FR-RPT-002, FR-RPT-003.
///
/// The query beneath the trend lines. Not built over [ComparePeriods], even
/// though `ROADMAP.md` once pencilled it in for this. A delta is the wrong
/// shape for a line, which plots *levels*; and calling it once per point
/// would cost two `spendingByCategory` queries per point — 46 for a
/// two-year monthly line — against the one bucketed statement
/// [AnalyticsRepository.spendingTrend] runs. The cheaper-looking middle
/// option, `spendingByCategory` once per bucket, was measured rather than
/// assumed: `analytics_query_benchmark_test.dart` times it beside the single
/// statement and finds them within a few milliseconds on the host VM, which
/// pays no platform-channel round trip per call. On a device the loop pays one per
/// point and the statement pays one, so the statement is the option whose
/// cost does not grow with the number of points on the line.
///
/// Takes an [AnalyticsQuery] like the donut and the bars do, so FR-RPT-003's
/// account filter reaches it. A chart drawn under the same filter row as two
/// charts that honour it, but which quietly does not, is a line that looks
/// filtered and is not.
class GetSpendingTrend implements UseCase<SpendingTrend, AnalyticsQuery> {
  /// Creates the use case.
  const GetSpendingTrend(this._repository);

  final AnalyticsRepository _repository;

  /// The longest span still cut by day. Beyond it, by month.
  ///
  /// About a quarter: a Week or a Month from FR-RPT-002's picker plots one
  /// point per day, a Year or All plots one per month, and a custom interval
  /// falls whichever side its length puts it. Past this many daily points
  /// the labels stop fitting and the line stops reading as anything but
  /// noise, which is when the month becomes the honest unit.
  static const int maxDailySpanDays = 92;

  @override
  Future<Either<Failure, SpendingTrend>> call(AnalyticsQuery params) async {
    // The same check the donut and bars run, with the same sentence, so an
    // inverted custom interval reads identically on every card.
    final failure = GetSpendingByCategory.validate(params.range);
    if (failure != null) return Left(failure);

    final granularity = granularityFor(params.range);
    final buckets = granularity.bucketsOver(params.range);
    final points = await _repository.spendingTrend(params, granularity);
    return points.map(
      (sparse) => SpendingTrend(
        granularity: granularity,
        buckets: buckets,
        series: _densify(sparse, buckets),
      ),
    );
  }

  /// Day for a span up to [maxDailySpanDays], month beyond it.
  ///
  /// Static and public so a test can state the rule without a repository,
  /// the way `validate` is on the other analytics use cases.
  static TrendGranularity granularityFor(DateRange range) =>
      range.to.difference(range.from).inDays < maxDailySpanDays
      ? TrendGranularity.day
      : TrendGranularity.month;

  /// One series per category, every bucket filled, largest total first.
  ///
  /// A category missing from a bucket is zero there, not absent — the
  /// convention [ComparePeriods] already applies to a category missing from
  /// one period. Ties on total break by name, as `spendingByCategory` does,
  /// so the order is stable run to run.
  static List<CategorySeries> _densify(
    List<TrendPoint> points,
    List<DateTime> buckets,
  ) {
    final index = {for (var i = 0; i < buckets.length; i++) buckets[i]: i};
    final amounts = <int, List<int>>{};
    final identity = <int, TrendPoint>{};

    for (final point in points) {
      final column = index[point.bucket];
      // A point outside the buckets can only come from a repository
      // answering a different question than it was asked; dropping it is
      // the same as trusting the range, which every other use case does.
      if (column == null) continue;
      identity.putIfAbsent(point.categoryId, () => point);
      amounts.putIfAbsent(
        point.categoryId,
        () => List.filled(buckets.length, 0),
      )[column] += point.amountCents;
    }

    final series = [
      for (final MapEntry(key: id, value: row) in amounts.entries)
        CategorySeries(
          categoryId: id,
          name: identity[id]!.name,
          color: identity[id]!.color,
          amountsCents: List.unmodifiable(row),
        ),
    ];

    series.sort((a, b) {
      final byTotal = b.totalCents.compareTo(a.totalCents);
      return byTotal != 0 ? byTotal : a.name.compareTo(b.name);
    });
    return series;
  }
}
