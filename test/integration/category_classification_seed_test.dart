@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/dev_seed.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:moneyora/features/analytics/data/repositories/analytics_repository_impl.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/usecases/classify_categories.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compute_category_statistics.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The classifier against `dev_seed`'s 24 months, whose shapes were
/// generated so that each verdict here is a known answer (see `DevSeed`).
/// Both halves of E-07's rule run on the same data: at 24 months Gifts must
/// come back Seasonal, at 6 the same rows must come back Variable.
void main() {
  sqfliteFfiInit();

  late Database db;
  late ClassifyCategories classify;

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

    classify = ClassifyCategories(
      ComputeCategoryStatistics(
        AnalyticsRepositoryImpl(AnalyticsLocalDataSourceImpl(db)),
      ),
    );
  });

  tearDown(() => db.close());

  Future<Map<String, CategoryClassification>> over(
    LookbackWindow window,
  ) async {
    final result = await classify(window);
    return result.fold(
      (f) => fail('unexpected failure: $f'),
      (all) => {for (final c in all) c.name: c},
    );
  }

  group('over 24 months', () {
    test('Bills is Fixed', () async {
      expect((await over(twoYears))['Bills']!.type, ExpenseType.fixed);
    });

    test('Gifts is Seasonal, in April and December', () async {
      final gifts = (await over(twoYears))['Gifts']!;

      expect(gifts.type, ExpenseType.seasonal);
      expect(gifts.seasonalMonths, [4, 12]);
    });

    test('Car is Variable — its climb is a trend, not a class', () async {
      expect((await over(twoYears))['Car']!.type, ExpenseType.variable);
    });

    test('Food is Variable, by 0.007 of CV on this fixture', () async {
      // The seed's Food lands at CV 0.157 over monthly totals (HANDOFF.md,
      // PR #66). The SDD's line is 0.15 and is kept; the fixture is
      // deterministic, so the margin is thin but not flaky.
      final food = (await over(twoYears))['Food']!;

      expect(food.statistics.coefficientOfVariation, greaterThan(0.15));
      expect(food.statistics.coefficientOfVariation, lessThan(0.17));
      expect(food.type, ExpenseType.variable);
    });

    test('Pets is classified from its three rows, not refused', () async {
      final pets = (await over(twoYears))['Pets']!;

      expect(pets.statistics.transactionCount, 3);
      expect(pets.type, ExpenseType.variable);
      expect(pets.seasonalMonths, isEmpty);
    });
  });

  group('over 6 months (E-07 below the gate)', () {
    test('Gifts is Variable, though April 2026 is a spike in view', () async {
      final gifts = (await over(halfYear))['Gifts']!;
      final april = gifts
          .statistics
          .monthlyTotalsCents[halfYear.indexOf(DateTime(2026, 4))];

      // The index alone would say Seasonal; the gate says no.
      expect(
        april,
        greaterThan(
          ClassifyCategories.seasonalIndex * gifts.statistics.meanCents,
        ),
      );
      expect(gifts.type, ExpenseType.variable);
      expect(gifts.seasonalMonths, isEmpty);
    });

    test('Bills is still Fixed', () async {
      expect((await over(halfYear))['Bills']!.type, ExpenseType.fixed);
    });

    test('Car is Fixed with a rising trend: six months of an 8% climb stay '
        'within 15% of their mean', () async {
      // CV cannot see a monotone drift over a short window; the trend can.
      // The allocator (FR-PLN-007) applies its trend buffer by the trend,
      // not by the class, or a case like this one gets no buffer at all.
      final car = (await over(halfYear))['Car']!;

      expect(car.statistics.coefficientOfVariation, lessThan(0.15));
      expect(car.type, ExpenseType.fixed);
      expect(car.statistics.trend, TrendDirection.rising);
    });

    test('nothing is Seasonal', () async {
      final all = await over(halfYear);

      expect(
        all.values.map((c) => c.type),
        isNot(contains(ExpenseType.seasonal)),
      );
    });
  });
}
