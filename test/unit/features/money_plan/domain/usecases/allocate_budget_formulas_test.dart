import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/usecases/allocate_budget.dart';

/// Each formula on its own, before any of them are composed.

final twoYears = LookbackWindow(months: 24, lastMonth: DateTime(2026, 8));
final halfYear = LookbackWindow(months: 6, lastMonth: DateTime(2026, 8));

CategoryStatistics _stats(List<int> totals) => CategoryStatistics.of(
  categoryId: 1,
  name: 'Food',
  monthlyTotalsCents: totals,
  transactionCount: totals.length,
);

CategoryClassification _classified(
  List<int> totals, {
  ExpenseType type = ExpenseType.variable,
  List<int> seasonalMonths = const [],
}) => CategoryClassification(
  statistics: _stats(totals),
  type: type,
  seasonalMonths: seasonalMonths,
);

/// [base] in every month of [window], [spikes] (calendar month → amount)
/// replacing it where that month falls.
List<int> _series(
  LookbackWindow window, {
  required int base,
  Map<int, int> spikes = const {},
}) => [for (final start in window.monthStarts) spikes[start.month] ?? base];

void main() {
  group('recentAverage (the Fixed base)', () {
    test('is the mean of the last three months only', () {
      final stats = _stats([100, 100, 100, 400, 500, 600]);

      expect(AllocateBudget.recentAverage(stats), 500);
    });

    test('follows a step, which the whole-window mean would not', () {
      // Rent went up four months ago: a 24-month mean would budget the old
      // rent; the recent average budgets the new one.
      final stats = _stats([
        ...List.filled(20, 40000),
        ...List.filled(4, 45000),
      ]);

      expect(AllocateBudget.recentAverage(stats), 45000);
      expect(stats.meanCents, lessThan(45000));
    });

    test('uses every month when the window is shorter than three', () {
      expect(AllocateBudget.recentAverage(_stats([100, 300])), 200);
      expect(AllocateBudget.recentAverage(_stats([700])), 700);
    });
  });

  group('weightedMovingAverage (the Variable base)', () {
    test('is 60% of the recent mean plus 40% of the older mean', () {
      // Older three: mean 100. Recent three: mean 500.
      final stats = _stats([100, 100, 100, 400, 500, 600]);

      expect(
        AllocateBudget.weightedMovingAverage(stats),
        closeTo(0.6 * 500 + 0.4 * 100, 1e-9),
      );
    });

    test('the older mean covers every month before the recent three', () {
      final totals = [...List.filled(21, 100), 1000, 1000, 1000];

      expect(
        AllocateBudget.weightedMovingAverage(_stats(totals)),
        closeTo(0.6 * 1000 + 0.4 * 100, 1e-9),
      );
    });

    test('with exactly three months the recent mean carries it all', () {
      // Nothing older to weigh: not 60% of the recent mean.
      final stats = _stats([400, 500, 600]);

      expect(AllocateBudget.weightedMovingAverage(stats), 500);
    });

    test('with fewer than three months, likewise', () {
      expect(AllocateBudget.weightedMovingAverage(_stats([200, 400])), 300);
      expect(AllocateBudget.weightedMovingAverage(_stats([900])), 900);
    });

    test('a quiet month counts as zero, not as absent', () {
      final stats = _stats([100, 100, 100, 0, 0, 600]);

      expect(
        AllocateBudget.weightedMovingAverage(stats),
        closeTo(0.6 * 200 + 0.4 * 100, 1e-9),
      );
    });
  });

  group('seasonalMultiplier', () {
    test("is the month's own mean over the mean of every month", () {
      // 22 months at 100, two Decembers at 1000: mean 175.
      final stats = _stats(_series(twoYears, base: 100, spikes: {12: 1000}));

      expect(stats.meanCents, 175);
      expect(
        AllocateBudget.seasonalMultiplier(stats, twoYears, 12),
        closeTo(1000 / 175, 1e-9),
      );
    });

    test('averages the years when they differ', () {
      final totals = _series(twoYears, base: 100);
      totals[3] = 800; // December 2024
      totals[15] = 1200; // December 2025
      final stats = _stats(totals);

      expect(
        AllocateBudget.seasonalMultiplier(stats, twoYears, 12),
        closeTo(1000 / stats.meanCents, 1e-9),
      );
    });

    test('is below one for a quiet month of a spiky category', () {
      final stats = _stats(_series(twoYears, base: 100, spikes: {12: 1000}));

      expect(
        AllocateBudget.seasonalMultiplier(stats, twoYears, 7),
        closeTo(100 / 175, 1e-9),
      );
    });

    test('is 1.0 when the window does not hold that month', () {
      // March–August: no December to learn from.
      final stats = _stats(_series(halfYear, base: 100));

      expect(AllocateBudget.seasonalMultiplier(stats, halfYear, 12), 1.0);
    });

    test('is 1.0 for statistics over a different span than the window', () {
      expect(
        AllocateBudget.seasonalMultiplier(_stats([100, 100]), twoYears, 12),
        1.0,
      );
    });

    test('is 1.0 when nothing was spent at all', () {
      final stats = _stats(List.filled(24, 0));

      expect(AllocateBudget.seasonalMultiplier(stats, twoYears, 12), 1.0);
    });
  });

  group('trendFactor', () {
    test('rising is +8%, falling is −5%, flat is unchanged', () {
      expect(AllocateBudget.trendFactor(TrendDirection.rising), 1.08);
      expect(AllocateBudget.trendFactor(TrendDirection.falling), 0.95);
      expect(AllocateBudget.trendFactor(TrendDirection.flat), 1.0);
    });
  });

  group('distribute (proportional, summing exactly)', () {
    test('keeps proportions and hits the total to the cent', () {
      final shares = AllocateBudget.distribute([300, 200, 100], 1000);

      expect(shares, [500, 333, 167]);
      expect(shares.fold(0, (a, b) => a + b), 1000);
    });

    test('hands the short cents to the largest fractional parts', () {
      // 100 / 3 each = 33.33..: floors sum to 99, one cent short, and the
      // parts tie, so the earliest gets it.
      expect(AllocateBudget.distribute([1, 1, 1], 100), [34, 33, 33]);
    });

    test('never differs from exact by more than a cent per share', () {
      final amounts = [1234567, 89, 4321, 1, 999999];
      const total = 7777777;
      final shares = AllocateBudget.distribute(amounts, total);
      final sum = amounts.fold(0, (a, b) => a + b);

      expect(shares.fold(0, (a, b) => a + b), total);
      for (var i = 0; i < amounts.length; i++) {
        expect((shares[i] - amounts[i] * total / sum).abs(), lessThan(1));
      }
    });

    test('scales down as well as up', () {
      expect(AllocateBudget.distribute([600, 400], 100), [60, 40]);
    });

    test('a zero total is zero everywhere', () {
      expect(AllocateBudget.distribute([600, 400], 0), [0, 0]);
    });

    test('all-zero amounts share the total equally', () {
      expect(AllocateBudget.distribute([0, 0, 0], 10), [4, 3, 3]);
    });

    test('nothing to distribute across is nothing', () {
      expect(AllocateBudget.distribute([], 500), isEmpty);
    });

    test('a single share takes the whole total', () {
      expect(AllocateBudget.distribute([123], 456), [456]);
    });
  });

  group('allocate (one category, composed)', () {
    test('Fixed: the recent average for a whole month, no factors', () {
      final c = _classified([
        ...List.filled(21, 40000),
        45000,
        45000,
        45000,
      ], type: ExpenseType.fixed);

      final a = AllocateBudget.allocate(c, twoYears, PlanPeriod.month(2026, 9));

      expect(a.baseMonthlyCents, 45000);
      expect(a.seasonalFactor, 1.0);
      expect(a.trendFactor, AllocateBudget.trendFactor(c.statistics.trend));
      expect(a.allocationCents, (45000 * a.trendFactor).round());
      expect(a.dailyAllowanceCents, a.allocationCents ~/ 30);
    });

    test('Variable: the weighted moving average', () {
      final c = _classified([100, 100, 100, 400, 500, 600]);

      final a = AllocateBudget.allocate(c, halfYear, PlanPeriod.month(2026, 9));

      expect(a.baseMonthlyCents, 340);
      expect(a.allocationCents, (340 * a.trendFactor).round());
    });

    test('the trend buffer applies to a Fixed category too', () {
      // The Car finding: Fixed by CV over six months, rising by slope.
      final totals = [1000, 1080, 1166, 1260, 1360, 1469];
      final c = _classified(totals, type: ExpenseType.fixed);
      expect(c.statistics.trend, TrendDirection.rising);

      final a = AllocateBudget.allocate(c, halfYear, PlanPeriod.month(2026, 9));

      expect(a.trendFactor, 1.08);
      expect(a.baseMonthlyCents, ((1260 + 1360 + 1469) / 3).round());
      expect(a.allocationCents, ((1260 + 1360 + 1469) / 3 * 1.08).round());
    });

    test('a falling category is reduced by 5%, whatever its class', () {
      final c = _classified([1500, 1400, 1300, 1200, 1100, 1000]);

      final a = AllocateBudget.allocate(c, halfYear, PlanPeriod.month(2026, 9));

      // Older mean 1400, recent mean 1100: base 1220, then −5%.
      expect(a.trendFactor, 0.95);
      expect(a.baseMonthlyCents, 1220);
      expect(a.allocationCents, (1220 * 0.95).round());
    });

    test('Seasonal: the multiplier applies in a spike month', () {
      final totals = _series(twoYears, base: 100, spikes: {12: 1000});
      final c = _classified(
        totals,
        type: ExpenseType.seasonal,
        seasonalMonths: const [12],
      );
      final stats = c.statistics;
      final base = AllocateBudget.weightedMovingAverage(stats);
      final index = AllocateBudget.seasonalMultiplier(stats, twoYears, 12);

      final a = AllocateBudget.allocate(
        c,
        twoYears,
        PlanPeriod.month(2026, 12),
      );

      // What December costs: the overall mean times December's index —
      // which is the mean of the Decembers, 1000 — not the weighted base
      // times the index.
      expect(stats.meanCents * index, closeTo(1000, 1e-9));
      expect(a.allocationCents, (1000 * a.trendFactor).round());
      expect(a.seasonalFactor, closeTo(1000 / base, 1e-9));
    });

    test('Seasonal: the spike budget does not move with the recent months', () {
      // Same Decembers, but the last three months are quiet in one series
      // and busy in the other: the weighted base differs, December's
      // budget must not.
      final quiet = _series(twoYears, base: 100, spikes: {12: 1000});
      final busy = [...quiet]..replaceRange(21, 24, [300, 300, 300]);
      final a = AllocateBudget.allocate(
        _classified(
          quiet,
          type: ExpenseType.seasonal,
          seasonalMonths: const [12],
        ),
        twoYears,
        PlanPeriod.month(2026, 12),
      );
      final b = AllocateBudget.allocate(
        _classified(
          busy,
          type: ExpenseType.seasonal,
          seasonalMonths: const [12],
        ),
        twoYears,
        PlanPeriod.month(2026, 12),
      );

      expect(a.baseMonthlyCents, isNot(b.baseMonthlyCents));
      expect(a.allocationCents / a.trendFactor, closeTo(1000, 0.5));
      expect(b.allocationCents / b.trendFactor, closeTo(1000, 0.5));
    });

    test('Seasonal: no multiplier in a month that is not a spike', () {
      final totals = _series(twoYears, base: 100, spikes: {12: 1000});
      final c = _classified(
        totals,
        type: ExpenseType.seasonal,
        seasonalMonths: const [12],
      );
      final base = AllocateBudget.weightedMovingAverage(c.statistics);

      final a = AllocateBudget.allocate(
        c,
        twoYears,
        PlanPeriod.month(2026, 10),
      );

      expect(a.seasonalFactor, 1.0);
      expect(a.allocationCents, (base * a.trendFactor).round());
    });

    test('a period across two months weights each by the days covered, '
        'the multiplier on the spike month\'s days only', () {
      final totals = _series(twoYears, base: 100, spikes: {12: 1000});
      final c = _classified(
        totals,
        type: ExpenseType.seasonal,
        seasonalMonths: const [12],
      );
      final stats = c.statistics;
      final base = AllocateBudget.weightedMovingAverage(stats);
      final index = AllocateBudget.seasonalMultiplier(stats, twoYears, 12);
      // 28 Nov – 4 Dec: 3/30 of November, 4/31 of December.
      final week = PlanPeriod(
        from: DateTime(2026, 11, 28),
        to: DateTime(2026, 12, 4),
      );

      final a = AllocateBudget.allocate(c, twoYears, week);

      final december = stats.meanCents * index; // what a December costs
      final expected = base * (3 / 30) + december * (4 / 31);
      expect(a.allocationCents, (expected * a.trendFactor).round());
      expect(a.dailyAllowanceCents, a.allocationCents ~/ 7);
    });

    test('a year is twelve months, each spike month multiplied', () {
      final totals = _series(twoYears, base: 100, spikes: {4: 700, 12: 1000});
      final c = _classified(
        totals,
        type: ExpenseType.seasonal,
        seasonalMonths: const [4, 12],
      );
      final stats = c.statistics;
      final base = AllocateBudget.weightedMovingAverage(stats);
      final april = AllocateBudget.seasonalMultiplier(stats, twoYears, 4);
      final december = AllocateBudget.seasonalMultiplier(stats, twoYears, 12);
      final year = PlanPeriod(from: DateTime(2027), to: DateTime(2027, 12, 31));

      final a = AllocateBudget.allocate(c, twoYears, year);

      final mean = stats.meanCents;
      final expected = base * 10 + mean * april + mean * december;
      expect(a.allocationCents, (expected * a.trendFactor).round());
    });

    test('a shorter period is a proportional share of the month', () {
      final c = _classified(List.filled(6, 3000), type: ExpenseType.fixed);
      final fifteen = PlanPeriod.days(DateTime(2026, 9), 15);

      final a = AllocateBudget.allocate(c, halfYear, fifteen);

      expect(a.allocationCents, 1500);
      expect(a.dailyAllowanceCents, 100);
    });

    test('the daily allowance is floored, never rounded up', () {
      final c = _classified(List.filled(6, 1000), type: ExpenseType.fixed);

      final a = AllocateBudget.allocate(c, halfYear, PlanPeriod.month(2026, 9));

      expect(a.allocationCents, 1000);
      expect(a.dailyAllowanceCents, 33);
      expect(a.dailyAllowanceCents * 30, lessThanOrEqualTo(a.allocationCents));
    });
  });
}
