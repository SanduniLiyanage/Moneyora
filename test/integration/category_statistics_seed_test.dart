@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/dev_seed.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:moneyora/features/analytics/data/repositories/analytics_repository_impl.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compute_category_statistics.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The statistics stage against the fixture it was built for: `dev_seed`'s
/// 24 months, whose shapes are documented on `DevSeed` so that each claim
/// here is a check against a known answer, not against the code's own output.
///
/// Runs the whole pipeline — real SQLite, the analytics datasource, the
/// repository seen as a `MonthlySpendingReader`, then the use case — because
/// E-05's point is that the rows come out of SQL and the arithmetic happens
/// in Dart, and a fake reader could not prove the seam between the two.
void main() {
  sqfliteFfiInit();

  late Database db;
  late ComputeCategoryStatistics compute;

  // The seed writes history *up to* this day, so August 2026 is the last
  // whole month and the 24-month window runs from September 2024.
  final end = DateTime(2026, 8, 31);
  final twoYears = LookbackWindow(months: 24, lastMonth: DateTime(2026, 8));

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

    compute = ComputeCategoryStatistics(
      AnalyticsRepositoryImpl(AnalyticsLocalDataSourceImpl(db)),
    );
  });

  tearDown(() => db.close());

  Future<Map<String, CategoryStatistics>> statsOver(
    LookbackWindow window,
  ) async {
    final result = await compute(window);
    return result.fold(
      (f) => fail('unexpected failure: $f'),
      (stats) => {for (final s in stats) s.name: s},
    );
  }

  test('every seeded expense category is described over 24 months', () async {
    final stats = await statsOver(twoYears);

    expect(stats.keys, containsAll(['Bills', 'Food', 'Gifts', 'Car', 'Pets']));
    expect(stats.containsKey('Salary'), isFalse, reason: 'income is not spend');
    for (final s in stats.values) {
      expect(s.monthCount, 24, reason: s.name);
    }
  });

  test('Bills is low-variance: CV below 0.15, the Fixed threshold', () async {
    final bills = (await statsOver(twoYears))['Bills']!;

    expect(bills.activeMonths, 24);
    expect(bills.transactionCount, 24);
    expect(bills.coefficientOfVariation, lessThan(0.15));
    expect(bills.trend, TrendDirection.flat);
    // Rent is Rs 45,000 give or take Rs 100.
    expect(bills.meanCents, closeTo(4500000, 10000));
    expect(bills.medianCents, closeTo(4500000, 10000));
    expect(bills.maxCents - bills.minCents, lessThanOrEqualTo(20000));
  });

  test('Gifts spikes in December (and April), well above its median', () async {
    final gifts = (await statsOver(twoYears))['Gifts']!;
    final months = twoYears.monthStarts;

    int totalIn(int year, int month) =>
        gifts.monthlyTotalsCents[months.indexOf(DateTime(year, month))];

    // Two Decembers, two Aprils and twenty quiet months: a spike month is
    // several times the mean, and the mean is far above the median.
    for (final spike in [totalIn(2024, 12), totalIn(2025, 12)]) {
      expect(spike, greaterThan(2 * gifts.meanCents));
    }
    expect(gifts.meanCents, greaterThan(3 * gifts.medianCents));
    // Spikes push the deviation past the mean: nowhere near Fixed.
    expect(gifts.coefficientOfVariation, greaterThan(0.5));
  });

  test('Car trends upward, as an 8% monthly climb should', () async {
    final car = (await statsOver(twoYears))['Car']!;

    expect(car.trend, TrendDirection.rising);
    expect(car.slopeCentsPerMonth / car.meanCents, greaterThan(0.05));
    expect(
      car.monthlyTotalsCents.last,
      greaterThan(car.monthlyTotalsCents.first * 3),
    );
    expect(car.transactionCount, greaterThanOrEqualTo(70));
  });

  test('Pets has three transactions in two years: too few to trust', () async {
    final pets = (await statsOver(twoYears))['Pets']!;

    expect(pets.transactionCount, 3);
    expect(pets.activeMonths, 3);
    expect(pets.medianCents, 0);
    // Almost every month is zero, so the deviation dwarfs the mean.
    expect(pets.coefficientOfVariation, greaterThan(1));
  });

  test('Food is busy and noisy, but level', () async {
    final food = (await statsOver(twoYears))['Food']!;

    final bills = (await statsOver(twoYears))['Bills']!;

    expect(food.activeMonths, 24);
    expect(food.transactionCount, greaterThan(400));
    // Its CV over monthly totals is 0.157 — near-daily noise averages out
    // per month, and it lands a hair above the 0.15 Fixed line. Asserted
    // against Bills rather than the threshold, which is the classifier's
    // call to make.
    expect(
      food.coefficientOfVariation,
      greaterThan(20 * bills.coefficientOfVariation),
    );
    expect(food.trend, TrendDirection.flat);
  });

  test('a 6-month window sees only its own months', () async {
    final stats = await statsOver(LookbackWindow.before(DateTime(2026, 9, 13)));

    expect(stats['Bills']!.monthCount, 6);
    expect(stats['Bills']!.transactionCount, 6);
    // Two of the three vet visits fall outside the last six months.
    expect(stats['Pets']!.transactionCount, 1);
  });

  test('the ordering puts the biggest monthly spend first', () async {
    final result = await compute(twoYears);
    final names = result.fold(
      (f) => fail('unexpected failure: $f'),
      (stats) => stats.map((s) => s.name).toList(),
    );

    expect(names.first, 'Bills');
    expect(names.last, 'Pets');
  });
}
