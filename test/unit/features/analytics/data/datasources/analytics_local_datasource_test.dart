@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/dev_seed.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Against a real in-memory SQLite, because every claim here is about what the
/// query does to real rows — that a transfer contributes nothing, that a split
/// lands on its parts, that `SUM` over no rows yields no row at all.
///
/// The second half runs against `dev_seed`, which is the point of that fixture
/// being deterministic: the shapes it generates are known, so the aggregate can
/// be checked against an expected answer rather than against itself.
void main() {
  sqfliteFfiInit();

  late Database db;
  late AnalyticsLocalDataSourceImpl analytics;

  const cash = 1;
  const card = 2;

  // Ids from `default_seed`'s ordering; asserted below rather than assumed.
  late int food;
  late int transport;
  late int salary;

  Future<int> insertExpense({
    required int categoryId,
    required int amountCents,
    required String date,
    int accountId = cash,
    bool isSplit = false,
    String type = 'expense',
  }) => db.insert('transactions', {
    'account_id': accountId,
    'category_id': categoryId,
    'amount_cents': amountCents,
    'type': type,
    'date': date,
    'is_split': isSplit ? 1 : 0,
    'created_at': '${date}T00:00:00Z',
    'updated_at': '${date}T00:00:00Z',
  });

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
    // The default seed creates one account; the transfer test needs two.
    await db.insert('accounts', {
      'id': card,
      'user_id': 1,
      'name': 'Payment card',
      'icon': 'card',
      'type': 'bank',
      'initial_balance_date': '2026-01-01',
      'created_at': '2026-01-01T00:00:00Z',
    });

    Future<int> idOf(String name) async {
      final rows = await db.query(
        'categories',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [name],
      );
      return rows.single['id']! as int;
    }

    food = await idOf('Food');
    transport = await idOf('Transport');
    salary = await idOf('Salary');

    analytics = AnalyticsLocalDataSourceImpl(db);
  });

  tearDown(() => db.close());

  group('the aggregate', () {
    test('totals each category and orders by the largest', () async {
      await insertExpense(
        categoryId: food,
        amountCents: 120000,
        date: '2026-08-03',
      );
      await insertExpense(
        categoryId: food,
        amountCents: 80000,
        date: '2026-08-14',
      );
      await insertExpense(
        categoryId: transport,
        amountCents: 500000,
        date: '2026-08-20',
      );

      final totals = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(totals.map((t) => t.name), ['Transport', 'Food']);
      expect(totals.first.amountCents, 500000);
      expect(totals.last.amountCents, 200000);
    });

    test('carries the colour, so the donut needs no second query', () async {
      await insertExpense(categoryId: food, amountCents: 1, date: '2026-08-03');

      final totals = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(totals.single.categoryId, food);
      expect(totals.single.color, isNotEmpty);
    });

    test('returns nothing at all for a period with no spending', () async {
      // Not a row of zeroes. `SUM` over no rows is null in SQLite, and a
      // caller that reads that as a total gets 0 for a category that has no
      // business appearing.
      final totals = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(totals, isEmpty);
    });
  });

  group('what must not be counted', () {
    test('income is not spending', () async {
      await insertExpense(
        categoryId: salary,
        amountCents: 9000000,
        date: '2026-08-01',
        type: 'income',
      );
      await insertExpense(
        categoryId: food,
        amountCents: 120000,
        date: '2026-08-03',
      );

      final totals = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(totals.map((t) => t.name), ['Food']);
    });

    test('a transfer contributes nothing to either side (E-02)', () async {
      // Two rows exist per transfer. A query that forgets this does not merely
      // include them — it counts the movement twice, and the error is
      // invisible in the output.
      await db.insert('transactions', {
        'account_id': cash,
        'amount_cents': 2500000,
        'type': 'transfer',
        'transfer_direction': 'out',
        'date': '2026-08-10',
        'created_at': '2026-08-10T00:00:00Z',
        'updated_at': '2026-08-10T00:00:00Z',
      });
      await db.insert('transactions', {
        'account_id': card,
        'amount_cents': 2500000,
        'type': 'transfer',
        'transfer_direction': 'in',
        'date': '2026-08-10',
        'created_at': '2026-08-10T00:00:00Z',
        'updated_at': '2026-08-10T00:00:00Z',
      });

      final totals = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(totals, isEmpty);
    });

    test('spending outside the range, at either edge', () async {
      await insertExpense(
        categoryId: food,
        amountCents: 100,
        date: '2026-07-31',
      );
      await insertExpense(
        categoryId: food,
        amountCents: 200,
        date: '2026-09-01',
      );
      await insertExpense(categoryId: food, amountCents: 4, date: '2026-08-01');
      await insertExpense(categoryId: food, amountCents: 8, date: '2026-08-31');

      final totals = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      // Both ends inclusive: 4 + 8, and neither neighbour.
      expect(totals.single.amountCents, 12);
    });
  });

  group('split expenses (E-04)', () {
    test('count against their parts, not against the parent', () async {
      // The parent carries the dominant category and the full amount; the
      // children carry the real breakdown. Summing both double-counts the
      // transaction; summing only the parent files it all under one category.
      final parent = await insertExpense(
        categoryId: food,
        amountCents: 300000,
        date: '2026-08-05',
        isSplit: true,
      );
      await db.insert('transaction_splits', {
        'transaction_id': parent,
        'category_id': food,
        'amount_cents': 200000,
      });
      await db.insert('transaction_splits', {
        'transaction_id': parent,
        'category_id': transport,
        'amount_cents': 100000,
      });

      final totals = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(
        {for (final t in totals) t.name: t.amountCents},
        {'Food': 200000, 'Transport': 100000},
      );
    });

    test('a split and an ordinary expense add up once each', () async {
      final parent = await insertExpense(
        categoryId: food,
        amountCents: 300000,
        date: '2026-08-05',
        isSplit: true,
      );
      await db.insert('transaction_splits', {
        'transaction_id': parent,
        'category_id': food,
        'amount_cents': 300000,
      });
      await insertExpense(
        categoryId: food,
        amountCents: 50000,
        date: '2026-08-06',
      );

      final totals = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(totals.single.amountCents, 350000);
    });
  });

  group('against the seeded 24 months', () {
    // `dev_seed` generates deliberately shaped categories. Because it is
    // deterministic, the aggregate can be checked against what the fixture is
    // known to contain rather than against its own output.
    late DateTime end;

    setUp(() async {
      end = DateTime(2026, 8, 31);
      await DevSeed.populate(db, endDate: end);
    });

    test('every seeded category appears over the whole span', () async {
      final totals = await analytics.spendingByCategory(
        from: DateTime(2024, 9),
        to: end,
      );

      expect(
        totals.map((t) => t.name),
        containsAll(<String>['Bills', 'Food', 'Gifts', 'Car', 'Pets']),
      );
      expect(totals.every((t) => t.amountCents > 0), isTrue);
    });

    test('Bills is near-identical month to month (a fixed cost)', () async {
      final july = await analytics.spendingByCategory(
        from: DateTime(2026, 7),
        to: DateTime(2026, 7, 31),
      );
      final august = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: end,
      );

      final a = july.firstWhere((t) => t.name == 'Bills').amountCents;
      final b = august.firstWhere((t) => t.name == 'Bills').amountCents;

      expect((a - b).abs() / a, lessThan(0.15));
    });

    test('Gifts spikes in December against a quiet month', () async {
      final december = await analytics.spendingByCategory(
        from: DateTime(2025, 12),
        to: DateTime(2025, 12, 31),
      );
      final october = await analytics.spendingByCategory(
        from: DateTime(2025, 10),
        to: DateTime(2025, 10, 31),
      );

      final spike = december.firstWhere((t) => t.name == 'Gifts').amountCents;
      final quiet = october
          .where((t) => t.name == 'Gifts')
          .fold(0, (sum, t) => sum + t.amountCents);

      expect(spike, greaterThan(quiet));
    });

    test('the total is the sum of its categories, in one period', () async {
      final august = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: end,
      );

      final summed = august.fold(0, (sum, t) => sum + t.amountCents);
      final expected = await db.rawQuery(
        'SELECT SUM(amount_cents) AS total FROM transactions '
        "WHERE type = 'expense' AND date >= ? AND date <= ?",
        ['2026-08-01', '2026-08-31'],
      );

      expect(summed, (expected.single['total']! as num).toInt());
    });
  });
}
