/// One category's spending, described statistically. FR-PLN-005.
///
/// Computed over *monthly totals* rather than over transactions: a budget is
/// set per period, so "how much does Food cost a month, and how steadily" is
/// the question, and a per-transaction deviation would only say that some
/// grocery runs are bigger than others. Computed in Dart, not SQL (E-05).
library;

import 'dart:math';

import 'package:equatable/equatable.dart';

/// Which way a category's monthly spending is moving. FR-PLN-005's trend
/// direction, and what FR-PLN-007's trend adjustment reads.
enum TrendDirection {
  /// Climbing faster than [CategoryStatistics.flatBand] a month.
  rising,

  /// Within the band either way.
  flat,

  /// Falling faster than the band.
  falling,
}

/// The statistics FR-PLN-005 names, for one category over a lookback window.
///
/// Amounts ([meanCents], [medianCents], [minCents], [maxCents]) are integer
/// minor units, rounded to the cent (E-06). [stdDevCents] and
/// [slopeCentsPerMonth] are a dispersion and a rate, not amounts, and stay
/// fractional because the classifier divides them.
class CategoryStatistics extends Equatable {
  /// Creates statistics from already-computed values. Prefer [of].
  const CategoryStatistics({
    required this.categoryId,
    required this.name,
    required this.monthlyTotalsCents,
    required this.transactionCount,
    required this.meanCents,
    required this.medianCents,
    required this.stdDevCents,
    required this.minCents,
    required this.maxCents,
    required this.slopeCentsPerMonth,
    required this.trend,
  });

  /// Computes every statistic from [monthlyTotalsCents], one entry per month
  /// of the window, oldest first, zero for a month with nothing spent.
  ///
  /// The standard deviation is the **sample** one, `n - 1` in the
  /// denominator (E-05): the population formula understates dispersion on
  /// exactly the short histories this app has. One month has nothing to
  /// deviate from, so it is 0 rather than undefined.
  ///
  /// The slope is an ordinary least-squares line through the totals against
  /// month index, in cents per month — the SDD's `linear_regression`.
  factory CategoryStatistics.of({
    required int categoryId,
    required String name,
    required List<int> monthlyTotalsCents,
    required int transactionCount,
  }) {
    if (monthlyTotalsCents.isEmpty) {
      throw ArgumentError.value(
        monthlyTotalsCents,
        'monthlyTotalsCents',
        'must cover at least one month',
      );
    }
    final n = monthlyTotalsCents.length;
    final totals = List<int>.unmodifiable(monthlyTotalsCents);
    final mean = totals.fold(0, (a, b) => a + b) / n;

    final sorted = [...totals]..sort();
    final median = n.isOdd
        ? sorted[n ~/ 2].toDouble()
        : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;

    var squares = 0.0;
    for (final t in totals) {
      squares += (t - mean) * (t - mean);
    }
    final stdDev = n < 2 ? 0.0 : sqrt(squares / (n - 1));

    // OLS slope: sum((x - xBar)(y - yBar)) / sum((x - xBar)^2), x the index.
    final xBar = (n - 1) / 2;
    var covariance = 0.0;
    var variance = 0.0;
    for (var i = 0; i < n; i++) {
      covariance += (i - xBar) * (totals[i] - mean);
      variance += (i - xBar) * (i - xBar);
    }
    final slope = variance == 0 ? 0.0 : covariance / variance;

    return CategoryStatistics(
      categoryId: categoryId,
      name: name,
      monthlyTotalsCents: totals,
      transactionCount: transactionCount,
      meanCents: mean.round(),
      medianCents: median.round(),
      stdDevCents: stdDev,
      minCents: sorted.first,
      maxCents: sorted.last,
      slopeCentsPerMonth: slope,
      trend: trendOf(slope: slope, meanCents: mean),
    );
  }

  /// A slope smaller than this fraction of the mean, per month, is flat.
  ///
  /// Two percent a month: a real drift (the seed's Car climbs 8% a month)
  /// clears it by a wide margin, and the month-to-month noise of a busy
  /// variable category fits well inside it over any window FR-PLN-003
  /// allows.
  static const double flatBand = 0.02;

  /// [slope] read against [meanCents]: the direction FR-PLN-007 adjusts for.
  /// Nothing spent is nothing moving.
  static TrendDirection trendOf({
    required double slope,
    required double meanCents,
  }) {
    if (meanCents <= 0) return TrendDirection.flat;
    final relative = slope / meanCents;
    if (relative > flatBand) return TrendDirection.rising;
    if (relative < -flatBand) return TrendDirection.falling;
    return TrendDirection.flat;
  }

  /// The category these describe.
  final int categoryId;

  /// The category's display name, e.g. `Food`.
  final String name;

  /// What was spent each month of the window, oldest first; zero for a
  /// month with nothing spent. The series every other field is derived from.
  final List<int> monthlyTotalsCents;

  /// How many expense rows the window holds — FR-PLN-005's transaction
  /// frequency, and what FR-PLN-010's data sufficiency reads.
  final int transactionCount;

  /// Mean monthly spend.
  final int meanCents;

  /// Median monthly spend.
  final int medianCents;

  /// Sample standard deviation of the monthly totals.
  final double stdDevCents;

  /// The quietest month.
  final int minCents;

  /// The busiest month.
  final int maxCents;

  /// How much the monthly total moves per month, by least squares.
  final double slopeCentsPerMonth;

  /// Which way the spending is going.
  final TrendDirection trend;

  /// How many months the window spans.
  int get monthCount => monthlyTotalsCents.length;

  /// How many of those months had any spending.
  int get activeMonths => monthlyTotalsCents.where((t) => t > 0).length;

  /// Standard deviation over mean — the SDD's `CV`, what classifies Fixed
  /// (< 0.15) and scores confidence. Zero when nothing was spent.
  double get coefficientOfVariation =>
      meanCents == 0 ? 0 : stdDevCents / meanCents;

  @override
  List<Object?> get props => [
    categoryId,
    name,
    monthlyTotalsCents,
    transactionCount,
    meanCents,
    medianCents,
    stdDevCents,
    minCents,
    maxCents,
    slopeCentsPerMonth,
    trend,
  ];
}
