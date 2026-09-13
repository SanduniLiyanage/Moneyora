import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/usecases/score_confidence.dart';

LookbackWindow _window(int months) =>
    LookbackWindow(months: months, lastMonth: DateTime(2026, 8));

/// Statistics with exactly [activeMonths] non-zero months out of [total],
/// shaped to a chosen coefficient of variation: the active months
/// alternate `base ± spread`, so `CV = sd / mean` is set by [spread].
///
/// Zeros count in the CV too, so [cv] is only exact when every month is
/// active; the tests that need an exact CV use full windows.
CategoryStatistics _stats({
  required int activeMonths,
  int? total,
  int base = 1000,
  int spread = 0,
  int rows = 1,
}) {
  final n = total ?? activeMonths;
  final totals = List.filled(n, 0);
  for (var i = 0; i < activeMonths; i++) {
    totals[n - 1 - i] = base + (i.isEven ? spread : -spread);
  }
  return CategoryStatistics.of(
    categoryId: 1,
    name: 'Food',
    monthlyTotalsCents: totals,
    transactionCount: activeMonths * rows,
  );
}

void main() {
  group('the levels compare', () {
    test('worst first, so a cap is a min', () {
      expect(
        ConfidenceLevel.high.cappedAt(ConfidenceLevel.medium),
        ConfidenceLevel.medium,
      );
      expect(
        ConfidenceLevel.low.cappedAt(ConfidenceLevel.medium),
        ConfidenceLevel.low,
      );
      expect(
        ConfidenceLevel.medium.cappedAt(ConfidenceLevel.high),
        ConfidenceLevel.medium,
      );
    });
  });

  group('data points are active months, not rows', () {
    test('a category seen in 3 months is 3 data points however many rows', () {
      final stats = _stats(activeMonths: 3, total: 24, rows: 40);

      final score = ScoreConfidence.score(stats, _window(24));

      expect(stats.transactionCount, 120);
      expect(score.dataPoints, 3);
      expect(score.level, ConfidenceLevel.low);
    });

    test('a category seen every month for 24 months is 24 data points', () {
      final stats = _stats(activeMonths: 24, rows: 22);

      expect(ScoreConfidence.score(stats, _window(24)).dataPoints, 24);
    });
  });

  group('the months threshold, at its edges', () {
    // Steady series over a window exactly as long as the count, so the CV
    // is 0 and only the count decides. Read before the cap: a window under
    // 24 months holds every level to Medium, which is E-07's rule, not
    // this one — the cap is tested on its own below.
    ConfidenceLevel earned(int months) => ScoreConfidence.score(
      _stats(activeMonths: months),
      _window(months),
    ).uncappedLevel;

    test('10 months is High, 9 is Medium', () {
      expect(earned(10), ConfidenceLevel.high);
      expect(earned(9), ConfidenceLevel.medium);
    });

    test('4 months is Medium, 3 is Low', () {
      expect(earned(4), ConfidenceLevel.medium);
      expect(earned(3), ConfidenceLevel.low);
    });

    test('a month with nothing spent is not a data point', () {
      // Ten active months of twenty-four: the count says High, and the
      // fourteen quiet months push the CV past 0.50 — Low on variance.
      // The point here is the count: 10, not 24.
      final score = ScoreConfidence.score(
        _stats(activeMonths: 10, total: 24),
        _window(24),
      );

      expect(score.dataPoints, 10);
      expect(score.coefficientOfVariation, greaterThan(0.5));
      expect(score.level, ConfidenceLevel.low);
    });
  });

  group('the CV threshold, at its edges', () {
    // 24 active months alternating 1000 ± s: sample sd is s·sqrt(24/23),
    // so CV = s/1000 · 1.0215. For a target CV c, s = c·1000/1.0215.
    test('High needs CV under 0.25: 0.2499 is High, 0.25 is Medium', () {
      final under = _stats(activeMonths: 24, spread: 244); // CV 0.2492
      final at = _stats(activeMonths: 24, spread: 245); // CV 0.2503

      expect(under.coefficientOfVariation, lessThan(0.25));
      expect(at.coefficientOfVariation, greaterThanOrEqualTo(0.25));
      expect(
        ScoreConfidence.score(under, _window(24)).level,
        ConfidenceLevel.high,
      );
      expect(
        ScoreConfidence.score(at, _window(24)).level,
        ConfidenceLevel.medium,
      );
    });

    test('Medium needs CV under 0.50: 0.499 is Medium, 0.50 is Low', () {
      final under = _stats(activeMonths: 24, spread: 489); // CV 0.4995
      final at = _stats(activeMonths: 24, spread: 490); // CV 0.5005

      expect(under.coefficientOfVariation, lessThan(0.50));
      expect(at.coefficientOfVariation, greaterThanOrEqualTo(0.50));
      expect(
        ScoreConfidence.score(under, _window(24)).level,
        ConfidenceLevel.medium,
      );
      expect(ScoreConfidence.score(at, _window(24)).level, ConfidenceLevel.low);
    });

    test('plenty of months with high variance is still Low', () {
      final noisy = _stats(activeMonths: 24, spread: 800); // CV 0.82

      expect(
        ScoreConfidence.score(noisy, _window(24)).level,
        ConfidenceLevel.low,
      );
    });

    test('a single month of history reads Low on count alone', () {
      // One month, one window: CV is 0, and 1 < 4.
      final one = _stats(activeMonths: 1);
      final score = ScoreConfidence.score(one, _window(1));

      expect(one.coefficientOfVariation, 0);
      expect(score.uncappedLevel, ConfidenceLevel.low);
      expect(score.level, ConfidenceLevel.low);
    });
  });

  group('the E-07 cap, independent of the thresholds', () {
    test('High on the data alone, capped at Medium in a 12-month window', () {
      final stats = _stats(activeMonths: 12); // steady: CV 0, 12 months

      final score = ScoreConfidence.score(stats, _window(12));

      expect(score.uncappedLevel, ConfidenceLevel.high);
      expect(score.level, ConfidenceLevel.medium);
      expect(score.isCappedByLookback, isTrue);
      expect(score.lookbackMonths, 12);
    });

    test('23 months is still capped; 24 is not', () {
      final capped = ScoreConfidence.score(
        _stats(activeMonths: 23),
        _window(23),
      );
      final free = ScoreConfidence.score(_stats(activeMonths: 24), _window(24));

      expect(capped.level, ConfidenceLevel.medium);
      expect(capped.isCappedByLookback, isTrue);
      expect(free.level, ConfidenceLevel.high);
      expect(free.isCappedByLookback, isFalse);
    });

    test('the cap never raises: Low stays Low in a short window', () {
      final score = ScoreConfidence.score(
        _stats(activeMonths: 3, total: 6),
        _window(6),
      );

      expect(score.level, ConfidenceLevel.low);
      expect(score.isCappedByLookback, isFalse);
    });

    test('in a 6-month window High is out of reach on the data alone, so '
        'the cap is not what holds it down', () {
      // Six months cannot hold ten active ones: Medium is earned, not
      // imposed, and the reason the wizard states is the count.
      final score = ScoreConfidence.score(_stats(activeMonths: 6), _window(6));

      expect(score.uncappedLevel, ConfidenceLevel.medium);
      expect(score.level, ConfidenceLevel.medium);
      expect(score.isCappedByLookback, isFalse);
      expect(score.dataPoints, 6);
    });
  });

  test('carries the numbers it decided from', () {
    final stats = _stats(activeMonths: 24, spread: 100);

    final score = ScoreConfidence.score(stats, _window(24));

    expect(score.dataPoints, 24);
    expect(score.coefficientOfVariation, stats.coefficientOfVariation);
    expect(score.lookbackMonths, 24);
  });
}
