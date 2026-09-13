import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_statistics.dart';

CategoryStatistics _of(List<int> totals, {int count = 0}) =>
    CategoryStatistics.of(
      categoryId: 1,
      name: 'Food',
      monthlyTotalsCents: totals,
      transactionCount: count,
    );

void main() {
  group('CategoryStatistics.of', () {
    test('mean, median, min and max over the monthly totals', () {
      final stats = _of([100, 300, 200, 400], count: 9);

      expect(stats.meanCents, 250);
      expect(stats.medianCents, 250);
      expect(stats.minCents, 100);
      expect(stats.maxCents, 400);
      expect(stats.transactionCount, 9);
      expect(stats.monthCount, 4);
    });

    test('median is the middle value for an odd count', () {
      expect(_of([900, 100, 500]).medianCents, 500);
    });

    test('mean and median round to the cent', () {
      // Mean 233.33.., median (100 + 301) / 2 = 200.5.
      expect(_of([100, 301, 299]).meanCents, 233);
      expect(_of([100, 301]).medianCents, 201);
    });

    test('standard deviation uses the sample formula, n - 1 (E-05)', () {
      // Deviations from the mean of 5: -3, -1, 1, 3. Squares sum to 20.
      // Sample: sqrt(20 / 3); population would be sqrt(20 / 4) = sqrt(5).
      final stats = _of([2, 4, 6, 8]);

      expect(stats.stdDevCents, closeTo(2.582, 0.001));
    });

    test('a single month has no deviation, not an undefined one', () {
      final stats = _of([4500]);

      expect(stats.stdDevCents, 0);
      expect(stats.slopeCentsPerMonth, 0);
      expect(stats.trend, TrendDirection.flat);
    });

    test('an identical series is zero dispersion and flat', () {
      final stats = _of(List.filled(12, 4500000));

      expect(stats.stdDevCents, 0);
      expect(stats.coefficientOfVariation, 0);
      expect(stats.trend, TrendDirection.flat);
    });

    test('coefficient of variation is the deviation over the mean', () {
      final stats = _of([2, 4, 6, 8]);

      expect(stats.coefficientOfVariation, closeTo(2.582 / 5, 0.001));
    });

    test('counts the months with any spending', () {
      expect(_of([0, 150, 0, 0, 200, 0]).activeMonths, 2);
    });

    test('a category with nothing spent is zero everywhere and flat', () {
      final stats = _of([0, 0, 0]);

      expect(stats.meanCents, 0);
      expect(stats.coefficientOfVariation, 0);
      expect(stats.trend, TrendDirection.flat);
    });

    test('refuses an empty series', () {
      expect(() => _of([]), throwsArgumentError);
    });

    test('the totals it keeps cannot be edited from outside', () {
      final stats = _of([1, 2, 3]);

      expect(() => stats.monthlyTotalsCents[0] = 9, throwsUnsupportedError);
    });
  });

  group('the trend', () {
    test('slope is the least-squares line in cents per month', () {
      // Exactly linear: 100 more each month.
      final stats = _of([1000, 1100, 1200, 1300, 1400, 1500]);

      expect(stats.slopeCentsPerMonth, closeTo(100, 1e-9));
      expect(stats.trend, TrendDirection.rising);
    });

    test('a steady fall reads as falling', () {
      final stats = _of([1500, 1400, 1300, 1200, 1100, 1000]);

      expect(stats.slopeCentsPerMonth, closeTo(-100, 1e-9));
      expect(stats.trend, TrendDirection.falling);
    });

    test('drift inside the flat band is flat', () {
      // 0.5% of the mean per month, a quarter of the band.
      final stats = _of([1000, 1005, 1010, 1015, 1020, 1025]);

      expect(stats.trend, TrendDirection.flat);
    });

    test('noise around a level is flat', () {
      final stats = _of([1000, 1300, 900, 1200, 1100, 1000, 1250, 950]);

      expect(stats.trend, TrendDirection.flat);
    });

    test('trendOf reads the slope against the mean', () {
      expect(
        CategoryStatistics.trendOf(slope: 30, meanCents: 1000),
        TrendDirection.rising,
      );
      expect(
        CategoryStatistics.trendOf(slope: -30, meanCents: 1000),
        TrendDirection.falling,
      );
      expect(
        CategoryStatistics.trendOf(slope: 10, meanCents: 1000),
        TrendDirection.flat,
      );
      expect(
        CategoryStatistics.trendOf(slope: 10, meanCents: 0),
        TrendDirection.flat,
      );
    });
  });
}
