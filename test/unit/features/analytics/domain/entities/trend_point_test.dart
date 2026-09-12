import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';

void main() {
  group('TrendGranularity.day', () {
    test('a bucket is the calendar day, with the time dropped', () {
      expect(
        TrendGranularity.day.bucketOf(DateTime(2026, 9, 9, 14, 30)),
        DateTime(2026, 9, 9),
      );
    });

    test('the next bucket rolls the month and the year over', () {
      expect(
        TrendGranularity.day.next(DateTime(2026, 9, 30)),
        DateTime(2026, 10, 1),
      );
      expect(
        TrendGranularity.day.next(DateTime(2026, 12, 31)),
        DateTime(2027, 1, 1),
      );
    });

    test('a month is every day of that month, inclusive', () {
      final buckets = TrendGranularity.day.bucketsOver(
        DateRange.month(2026, 2),
      );

      expect(buckets.length, 28);
      expect(buckets.first, DateTime(2026, 2, 1));
      expect(buckets.last, DateTime(2026, 2, 28));
    });

    test('a single day is one bucket', () {
      expect(
        TrendGranularity.day.bucketsOver(DateRange.day(DateTime(2026, 9, 9))),
        [DateTime(2026, 9, 9)],
      );
    });
  });

  group('TrendGranularity.month', () {
    test('a bucket is the first of the month', () {
      expect(
        TrendGranularity.month.bucketOf(DateTime(2026, 9, 17)),
        DateTime(2026, 9),
      );
    });

    test('the next bucket rolls the year over', () {
      expect(
        TrendGranularity.month.next(DateTime(2026, 12)),
        DateTime(2027, 1),
      );
    });

    test('a year is twelve buckets', () {
      final buckets = TrendGranularity.month.bucketsOver(DateRange.year(2026));

      expect(buckets.length, 12);
      expect(buckets.first, DateTime(2026, 1));
      expect(buckets.last, DateTime(2026, 12));
    });

    test('a range starting mid-month begins at that month, not the next', () {
      final buckets = TrendGranularity.month.bucketsOver(
        DateRange(from: DateTime(2026, 7, 15), to: DateTime(2026, 9, 2)),
      );

      expect(buckets, [
        DateTime(2026, 7),
        DateTime(2026, 8),
        DateTime(2026, 9),
      ]);
    });
  });
}
