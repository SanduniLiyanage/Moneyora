@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/dev_seed.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:moneyora/features/analytics/data/repositories/analytics_repository_impl.dart';
import 'package:moneyora/features/money_plan/domain/entities/allocation_request.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_mode.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/usecases/allocate_budget.dart';
import 'package:moneyora/features/money_plan/domain/usecases/classify_categories.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compute_category_statistics.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Confidence against `dev_seed`, through the whole pipeline, on the three
/// cases the allocator's handoff left for this stage to settle: Pets (three
/// rows), Food (hundreds of rows, CV 0.157) and Bills (24 rows, 24 months).
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
          for (final statement in v1Statements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        },
        version: v1SchemaVersion,
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

  Future<Map<String, CategoryAllocation>> over(LookbackWindow window) async {
    final result = await allocate(
      AllocationRequest(period: PlanPeriod.month(2026, 9), lookback: window),
    );
    return result.fold(
      (f) => fail('unexpected failure: $f'),
      (d) => {for (final a in d.allocations) a.name: a},
    );
  }

  group('over 24 months', () {
    test('Bills: 24 months, CV 0.001, Fixed — High', () async {
      final bills = (await over(twoYears))['Bills']!;

      expect(bills.confidence.dataPoints, 24);
      expect(bills.confidence.coefficientOfVariation, lessThan(0.01));
      expect(bills.confidence.level, ConfidenceLevel.high);
      expect(bills.confidence.isCappedByLookback, isFalse);
    });

    test('Food: 521 rows but 24 data points, CV 0.157 — High, on months '
        'not rows', () async {
      final food = (await over(twoYears))['Food']!;

      expect(food.statistics.transactionCount, greaterThan(400));
      expect(food.confidence.dataPoints, 24);
      expect(food.confidence.coefficientOfVariation, lessThan(0.25));
      expect(food.confidence.level, ConfidenceLevel.high);
    });

    test('Pets: 3 data points — Low, whatever the rows say', () async {
      final pets = (await over(twoYears))['Pets']!;

      expect(pets.statistics.transactionCount, 3);
      expect(pets.confidence.dataPoints, 3);
      expect(pets.confidence.level, ConfidenceLevel.low);
      // The 8% buffer it got on a three-row "trend" is now labelled as
      // untrustworthy rather than silently applied.
      expect(pets.trendFactor, 1.08);
    });

    test('Car: 24 months on a clean climb, but the CV includes the climb '
        '— Low', () async {
      final car = (await over(twoYears))['Car']!;

      expect(car.confidence.dataPoints, 24);
      expect(car.confidence.coefficientOfVariation, greaterThan(0.5));
      expect(car.confidence.level, ConfidenceLevel.low);
    });

    test('Gifts: Seasonal, and its spikes are its variance — Low', () async {
      final gifts = (await over(twoYears))['Gifts']!;

      expect(gifts.type, ExpenseType.seasonal);
      expect(gifts.confidence.coefficientOfVariation, greaterThan(1));
      expect(gifts.confidence.level, ConfidenceLevel.low);
    });
  });

  group('over 6 months (E-07)', () {
    test('Bills: steady, but six months — Medium, earned not capped', () async {
      final bills = (await over(halfYear))['Bills']!;

      expect(bills.confidence.dataPoints, 6);
      expect(bills.confidence.uncappedLevel, ConfidenceLevel.medium);
      expect(bills.confidence.level, ConfidenceLevel.medium);
      expect(bills.confidence.isCappedByLookback, isFalse);
    });

    test('Food: Fixed by CV over six months, still only Medium', () async {
      final food = (await over(halfYear))['Food']!;

      expect(food.type, ExpenseType.fixed);
      expect(food.confidence.level, ConfidenceLevel.medium);
    });

    test('Pets: one visit in six months — Low', () async {
      final pets = (await over(halfYear))['Pets']!;

      expect(pets.confidence.dataPoints, 1);
      expect(pets.confidence.level, ConfidenceLevel.low);
    });

    test('nothing is High', () async {
      final all = await over(halfYear);

      expect(
        all.values.map((a) => a.confidence.level),
        isNot(contains(ConfidenceLevel.high)),
      );
    });
  });

  test('confidence survives Option A scaling unchanged', () async {
    final free = await over(twoYears);
    final result = await allocate(
      AllocationRequest(
        period: PlanPeriod.month(2026, 9),
        lookback: twoYears,
        mode: const BudgetMode.total(10000000),
      ),
    );
    final scaled = result.fold(
      (f) => fail('unexpected failure: $f'),
      (d) => {for (final a in d.allocations) a.name: a},
    );

    for (final name in free.keys) {
      expect(scaled[name]!.confidence, free[name]!.confidence, reason: name);
    }
  });
}
