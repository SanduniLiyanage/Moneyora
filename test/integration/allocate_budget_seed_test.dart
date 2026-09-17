@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/dev_seed.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:moneyora/features/analytics/data/repositories/analytics_repository_impl.dart';
import 'package:moneyora/features/money_plan/domain/entities/allocation_request.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_mode.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan_draft.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/usecases/allocate_budget.dart';
import 'package:moneyora/features/money_plan/domain/usecases/classify_categories.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compute_category_statistics.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The allocator against `dev_seed`'s 24 months through the whole pipeline:
/// real SQLite, the datasource, the repository as both ports, statistics,
/// classification, allocation.
void main() {
  sqfliteFfiInit();

  late Database db;
  late AllocateBudget allocate;

  final end = DateTime(2026, 8, 31);
  final twoYears = LookbackWindow(months: 24, lastMonth: DateTime(2026, 8));
  final halfYear = LookbackWindow(months: 6, lastMonth: DateTime(2026, 8));

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          final batch = d.batch();
          // Every version, not v1 alone: a datasource writes the columns the
          // latest schema has, and a test over v1 would refuse them.
          for (final version in schemaMigrations.keys.toList()..sort()) {
            for (final statement in schemaMigrations[version]!) {
              batch.execute(statement);
            }
          }
          await batch.commit(noResult: true);
        },
        version: latestSchemaVersion,
      ),
    );
    await applyDefaultSeed(db);
    await DevSeed.populate(db, endDate: end);

    final repository = AnalyticsRepositoryImpl(
      AnalyticsLocalDataSourceImpl(db),
    );
    allocate = AllocateBudget(
      ClassifyCategories(ComputeCategoryStatistics(repository)),
      repository,
    );
  });

  tearDown(() => db.close());

  Future<MoneyPlanDraft> draft(
    PlanPeriod period, {
    LookbackWindow? lookback,
    BudgetMode mode = const BudgetMode.unconstrained(),
  }) async {
    final result = await allocate(
      AllocationRequest(
        period: period,
        lookback: lookback ?? twoYears,
        mode: mode,
      ),
    );
    return result.fold((f) => fail('unexpected failure: $f'), (d) => d);
  }

  Map<String, CategoryAllocation> byName(MoneyPlanDraft d) => {
    for (final a in d.allocations) a.name: a,
  };

  group('over 24 months, for September 2026', () {
    test('Bills gets its flat recent average, no factors', () async {
      final bills = byName(await draft(PlanPeriod.month(2026, 9)))['Bills']!;
      final totals = bills.statistics.monthlyTotalsCents;
      final recent = totals.sublist(totals.length - 3);

      expect(bills.type, ExpenseType.fixed);
      expect(bills.seasonalFactor, 1.0);
      expect(bills.trendFactor, 1.0);
      expect(
        bills.baseMonthlyCents,
        (recent.fold(0, (a, b) => a + b) / 3).round(),
      );
      expect(bills.allocationCents, bills.baseMonthlyCents);
      expect(bills.allocationCents, closeTo(4500000, 10000));
      expect(bills.dailyAllowanceCents, bills.allocationCents ~/ 30);
    });

    test('Car gets the weighted average plus the 8% trend buffer', () async {
      final car = byName(await draft(PlanPeriod.month(2026, 9)))['Car']!;
      final stats = car.statistics;
      final totals = stats.monthlyTotalsCents;
      final recent = totals.sublist(21);
      final older = totals.sublist(0, 21);
      double mean(List<int> xs) => xs.fold(0, (a, b) => a + b) / xs.length;
      final wma = 0.6 * mean(recent) + 0.4 * mean(older);

      expect(car.type, ExpenseType.variable);
      expect(stats.trend, TrendDirection.rising);
      expect(car.trendFactor, 1.08);
      expect(car.baseMonthlyCents, wma.round());
      expect(car.allocationCents, (wma * 1.08).round());
      // The buffer is visible: more than the weighted average alone.
      expect(car.allocationCents, greaterThan(car.baseMonthlyCents));
    });

    test('Gifts gets no seasonal multiplier in September', () async {
      final gifts = byName(await draft(PlanPeriod.month(2026, 9)))['Gifts']!;

      expect(gifts.type, ExpenseType.seasonal);
      expect(gifts.seasonalFactor, 1.0);
      expect(
        gifts.allocationCents,
        (gifts.baseMonthlyCents * gifts.trendFactor).round(),
      );
    });
  });

  group('Gifts across the year', () {
    test('December carries its own multiplier, from its own history', () async {
      final gifts = byName(await draft(PlanPeriod.month(2026, 12)))['Gifts']!;
      final expected = AllocateBudget.seasonalMultiplier(
        gifts.statistics,
        twoYears,
        12,
      );

      final stats = gifts.statistics;
      final months = twoYears.monthStarts;
      final decembers = [
        for (var i = 0; i < months.length; i++)
          if (months[i].month == 12) stats.monthlyTotalsCents[i],
      ];
      final decemberMean = decembers.fold(0, (a, b) => a + b) / 2;

      expect(expected, greaterThan(1.5));
      // Budgeted at what a December costs — the mean of the two seeded
      // Decembers — not at the weighted base times the index.
      expect(
        gifts.allocationCents,
        closeTo((decemberMean * gifts.trendFactor).round(), 1),
      );
      expect(gifts.allocationCents, greaterThan(3 * gifts.baseMonthlyCents));
      expect(gifts.seasonalFactor, greaterThan(1.5));
    });

    test('April carries its own, and it differs from December', () async {
      final april = byName(await draft(PlanPeriod.month(2027, 4)))['Gifts']!;
      final december = byName(
        await draft(PlanPeriod.month(2026, 12)),
      )['Gifts']!;

      expect(april.seasonalFactor, greaterThan(1.5));
      expect(
        april.seasonalFactor,
        isNot(closeTo(december.seasonalFactor, 1e-6)),
      );
    });

    test('a quiet month is the base alone', () async {
      for (final month in [10, 11]) {
        final gifts = byName(
          await draft(PlanPeriod.month(2026, month)),
        )['Gifts']!;
        expect(gifts.seasonalFactor, 1.0, reason: 'month $month');
      }
    });

    test('a week straddling November and December is multiplied on its '
        'December days only', () async {
      final week = PlanPeriod(
        from: DateTime(2026, 11, 28),
        to: DateTime(2026, 12, 4),
      );
      final gifts = byName(await draft(week))['Gifts']!;
      final december = AllocateBudget.seasonalMultiplier(
        gifts.statistics,
        twoYears,
        12,
      );
      final base = AllocateBudget.weightedMovingAverage(gifts.statistics);
      final decemberCost = gifts.statistics.meanCents * december;
      final expected =
          (base * 3 / 30 + decemberCost * 4 / 31) * gifts.trendFactor;

      expect(gifts.allocationCents, expected.round());
      expect(gifts.seasonalFactor, greaterThan(1.0));
      expect(gifts.seasonalFactor, lessThan(decemberCost / base));
    });
  });

  group('the Car finding, over six months', () {
    test('Fixed by class, rising by trend — and buffered anyway', () async {
      final car = byName(
        await draft(PlanPeriod.month(2026, 9), lookback: halfYear),
      )['Car']!;

      expect(car.type, ExpenseType.fixed);
      expect(car.statistics.trend, TrendDirection.rising);
      expect(car.trendFactor, 1.08);
      expect(
        car.baseMonthlyCents,
        AllocateBudget.recentAverage(car.statistics).round(),
      );
      expect(car.allocationCents, (car.baseMonthlyCents * 1.08).round());
    });
  });

  group('the modes, on the seed', () {
    test('Option A sums to the total exactly', () async {
      const total = 12345678;
      final d = await draft(
        PlanPeriod.month(2026, 9),
        mode: const BudgetMode.total(total),
      );

      expect(d.totalCents, total);
      expect(d.allocations.every((a) => a.allocationCents >= 0), isTrue);
    });

    test('Option B is income less savings, fixed at face value', () async {
      final d = await draft(
        PlanPeriod.month(2026, 9),
        mode: const BudgetMode.suggested(savingsTargetPct: 10),
      );
      final free = await draft(PlanPeriod.month(2026, 9));

      // Salary is about Rs 180,000 a month.
      expect(d.incomeCents, closeTo(18000000, 200000));
      expect(d.savingsTargetCents, (d.incomeCents! * 0.1).round());
      expect(
        byName(d)['Bills']!.allocationCents,
        byName(free)['Bills']!.allocationCents,
      );
      expect(d.totalCents, d.incomeCents! - d.savingsTargetCents!);
      expect(d.unallocatedCents, 0);
    });
  });

  test('every seeded expense category is allocated, income is not', () async {
    final d = await draft(PlanPeriod.month(2026, 9));
    final names = d.allocations.map((a) => a.name);

    expect(names, containsAll(['Bills', 'Food', 'Gifts', 'Car', 'Pets']));
    expect(names, isNot(contains('Salary')));
  });
}
