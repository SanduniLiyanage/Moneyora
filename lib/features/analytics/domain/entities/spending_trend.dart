/// Per-category spending over time, ready to draw. FR-RPT-005.
///
/// What `GetSpendingTrend` returns: one x-axis shared by every line, and one
/// dense series per category aligned to it. Dense, because a month with no
/// Food spending is a point at zero, not a break in the line — the same
/// "missing is zero" rule `ComparePeriods` applies to a category absent from
/// one of its two periods.
library;

import 'package:equatable/equatable.dart';

import 'trend_point.dart';

/// One category's line: an amount for every bucket in
/// [SpendingTrend.buckets], in the same order.
class CategorySeries extends Equatable {
  /// Creates a series.
  const CategorySeries({
    required this.categoryId,
    required this.name,
    required this.color,
    required this.amountsCents,
  });

  /// The category this line belongs to.
  final int categoryId;

  /// The category's display name, e.g. `Food`.
  final String name;

  /// The category's colour as stored, e.g. `#FF7043`.
  final String color;

  /// What was spent in each bucket, in integer minor units (E-06). Zero for
  /// a bucket with nothing spent; never negative.
  final List<int> amountsCents;

  /// The whole period's total for this category — what ranks the lines and
  /// what the legend states beside each.
  int get totalCents => amountsCents.fold(0, (sum, cents) => sum + cents);

  @override
  List<Object?> get props => [categoryId, name, color, amountsCents];
}

/// Spending by category over a period, cut into buckets. FR-RPT-005.
class SpendingTrend extends Equatable {
  /// Creates a trend.
  const SpendingTrend({
    required this.granularity,
    required this.buckets,
    required this.series,
  });

  /// How finely the period was cut.
  final TrendGranularity granularity;

  /// The start of every bucket in the period, in order, none skipped — the
  /// x-axis. [TrendGranularity.bucketsOver] produces it.
  final List<DateTime> buckets;

  /// One line per category with any spending in the period, largest total
  /// first — the order `spendingByCategory` returns totals in, so the donut
  /// and the trend name the same category first.
  final List<CategorySeries> series;

  /// True when nothing was spent anywhere in the period.
  bool get isEmpty => series.isEmpty;

  @override
  List<Object?> get props => [granularity, buckets, series];
}
