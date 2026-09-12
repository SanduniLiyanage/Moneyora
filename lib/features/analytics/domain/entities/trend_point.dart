/// One category's spending in one bucket of time. FR-RPT-005.
///
/// The unit `AnalyticsRepository.spendingTrend` returns: a *sparse* set of
/// points — a category with nothing spent in a bucket produces no row, the
/// same "nothing appears" convention `spendingByCategory` uses for a period
/// with nothing spent. `GetSpendingTrend` is what makes the series dense, so
/// that a quiet month plots as zero rather than as a gap in the line.
library;

import 'package:equatable/equatable.dart';

import '../repositories/analytics_repository.dart';

/// How finely a period is cut into points along a trend line. FR-RPT-005.
///
/// Two steps rather than three. A week is the obvious middle, but FR-SET-004
/// makes the first day of the week user-configurable in Sprint 7, and a week
/// bucket cut in SQL (`strftime('%W')` is Monday-first, always) would ignore
/// that setting silently. Day and month have no such parameter, so they are
/// the two that can be cut at the index today without a decision that has
/// to be undone later.
enum TrendGranularity {
  /// One point per calendar day.
  day,

  /// One point per calendar month.
  month;

  /// The start of the bucket [date] falls in — the date itself, or the first
  /// of its month. Any time of day is dropped, since a date column holds a
  /// date.
  DateTime bucketOf(DateTime date) => switch (this) {
    day => DateTime(date.year, date.month, date.day),
    month => DateTime(date.year, date.month),
  };

  /// The bucket after [bucket], which must itself be a bucket start.
  ///
  /// Calendar arithmetic rather than a `Duration`: a month is not a fixed
  /// number of days, and `DateTime(year, month + 1)` rolls the year over on
  /// its own.
  DateTime next(DateTime bucket) => switch (this) {
    day => DateTime(bucket.year, bucket.month, bucket.day + 1),
    month => DateTime(bucket.year, bucket.month + 1),
  };

  /// Every bucket start from the one [range] begins in to the one it ends
  /// in, inclusive and in order — the dense x-axis a trend line draws along.
  List<DateTime> bucketsOver(DateRange range) {
    final last = bucketOf(range.to);
    final buckets = <DateTime>[];
    for (var b = bucketOf(range.from); !b.isAfter(last); b = next(b)) {
      buckets.add(b);
    }
    return buckets;
  }
}

/// What one category cost in one bucket. FR-RPT-005.
class TrendPoint extends Equatable {
  /// Creates a point.
  const TrendPoint({
    required this.bucket,
    required this.categoryId,
    required this.name,
    required this.color,
    required this.amountCents,
  });

  /// The start of the bucket, as [TrendGranularity.bucketOf] would give it.
  final DateTime bucket;

  /// The category this point belongs to.
  final int categoryId;

  /// The category's display name, e.g. `Food`.
  final String name;

  /// The category's colour as stored, e.g. `#FF7043`.
  final String color;

  /// What was spent in this bucket, in integer minor units. Always positive
  /// (E-06): a bucket with nothing spent has no point at all.
  final int amountCents;

  @override
  List<Object?> get props => [bucket, categoryId, name, color, amountCents];
}
