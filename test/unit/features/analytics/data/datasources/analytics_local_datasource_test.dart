@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/dev_seed.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
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

  group('the account filter (FR-RPT-003)', () {
    test('counts only the account asked for', () async {
      await insertExpense(
        categoryId: food,
        amountCents: 120000,
        date: '2026-08-03',
      );
      await insertExpense(
        categoryId: transport,
        amountCents: 500000,
        date: '2026-08-04',
        accountId: card,
      );

      final onCash = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        accountId: cash,
      );

      expect(onCash.map((t) => t.name), ['Food']);
      expect(onCash.single.amountCents, 120000);
    });

    test('a null account id counts every account — All Accounts', () async {
      await insertExpense(
        categoryId: food,
        amountCents: 120000,
        date: '2026-08-03',
      );
      await insertExpense(
        categoryId: transport,
        amountCents: 500000,
        date: '2026-08-04',
        accountId: card,
      );

      final all = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(all.map((t) => t.name), ['Transport', 'Food']);
      expect(all.fold(0, (sum, t) => sum + t.amountCents), 620000);
    });

    test(
      'an account with no spending in the period is empty, not zeroes',
      () async {
        await insertExpense(
          categoryId: food,
          amountCents: 120000,
          date: '2026-08-03',
        );

        final onCard = await analytics.spendingByCategory(
          from: DateTime(2026, 8),
          to: DateTime(2026, 8, 31),
          accountId: card,
        );

        expect(onCard, isEmpty);
      },
    );

    test('a split lands on its parent account, keeping E-04 intact', () async {
      // The parts carry no account of their own; the parent row is what says
      // where the money left from, so filtering by account must follow it.
      final parent = await insertExpense(
        categoryId: food,
        amountCents: 300000,
        date: '2026-08-09',
        accountId: card,
        isSplit: true,
      );
      await db.insert('transaction_splits', {
        'transaction_id': parent,
        'category_id': food,
        'amount_cents': 100000,
      });
      await db.insert('transaction_splits', {
        'transaction_id': parent,
        'category_id': transport,
        'amount_cents': 200000,
      });

      final onCard = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        accountId: card,
      );
      final onCash = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        accountId: cash,
      );

      expect(onCard.map((t) => t.name), ['Transport', 'Food']);
      expect(onCard.fold(0, (sum, t) => sum + t.amountCents), 300000);
      expect(onCash, isEmpty);
    });

    test(
      'a transfer still contributes nothing, filtered or not (E-02)',
      () async {
        // The account filter narrows by `account_id`, which is exactly the
        // column both halves of a transfer carry — so this is the one place
        // the filter could plausibly have resurrected them.
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

        final onCash = await analytics.spendingByCategory(
          from: DateTime(2026, 8),
          to: DateTime(2026, 8, 31),
          accountId: cash,
        );
        final onCard = await analytics.spendingByCategory(
          from: DateTime(2026, 8),
          to: DateTime(2026, 8, 31),
          accountId: card,
        );

        expect(onCash, isEmpty);
        expect(onCard, isEmpty);
      },
    );
  });

  group('income for a period', () {
    test('totals income between the dates, inclusive', () async {
      await insertExpense(
        categoryId: salary,
        amountCents: 900000,
        date: '2026-08-01',
        type: 'income',
      );
      await insertExpense(
        categoryId: salary,
        amountCents: 100000,
        date: '2026-08-31',
        type: 'income',
      );

      final income = await analytics.incomeForPeriod(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(income, 1000000);
    });

    test('is zero, not null, for a period with no income', () async {
      // A plain SUM with no matching rows is NULL in SQLite — unlike the
      // grouped spendingByCategory query, there is no GROUP BY here to make
      // the row disappear instead.
      final income = await analytics.incomeForPeriod(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(income, 0);
    });

    test('excludes expenses and transfers', () async {
      await insertExpense(
        categoryId: food,
        amountCents: 50000,
        date: '2026-08-03',
      );
      await db.insert('transactions', {
        'account_id': cash,
        'amount_cents': 2500000,
        'type': 'transfer',
        'transfer_direction': 'in',
        'date': '2026-08-10',
        'created_at': '2026-08-10T00:00:00Z',
        'updated_at': '2026-08-10T00:00:00Z',
      });
      await insertExpense(
        categoryId: salary,
        amountCents: 900000,
        date: '2026-08-01',
        type: 'income',
      );

      final income = await analytics.incomeForPeriod(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(income, 900000);
    });

    test('excludes income outside the range, at either edge', () async {
      await insertExpense(
        categoryId: salary,
        amountCents: 100,
        date: '2026-07-31',
        type: 'income',
      );
      await insertExpense(
        categoryId: salary,
        amountCents: 200,
        date: '2026-09-01',
        type: 'income',
      );
      await insertExpense(
        categoryId: salary,
        amountCents: 4,
        date: '2026-08-01',
        type: 'income',
      );
      await insertExpense(
        categoryId: salary,
        amountCents: 8,
        date: '2026-08-31',
        type: 'income',
      );

      final income = await analytics.incomeForPeriod(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      // Both ends inclusive: 4 + 8, and neither neighbour.
      expect(income, 12);
    });
  });

  group('the account filter on income (FR-RPT-003, FR-RPT-004)', () {
    test('counts only the account asked for', () async {
      await insertExpense(
        categoryId: salary,
        amountCents: 8000000,
        date: '2026-08-01',
        type: 'income',
      );
      await insertExpense(
        categoryId: salary,
        amountCents: 1500000,
        date: '2026-08-02',
        accountId: card,
        type: 'income',
      );

      final onCash = await analytics.incomeForPeriod(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        accountId: cash,
      );

      expect(onCash, 8000000);
    });

    test('a null account id counts every account — All Accounts', () async {
      await insertExpense(
        categoryId: salary,
        amountCents: 8000000,
        date: '2026-08-01',
        type: 'income',
      );
      await insertExpense(
        categoryId: salary,
        amountCents: 1500000,
        date: '2026-08-02',
        accountId: card,
        type: 'income',
      );

      final all = await analytics.incomeForPeriod(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(all, 9500000);
    });

    test('an account with no income is zero, not null', () async {
      await insertExpense(
        categoryId: salary,
        amountCents: 8000000,
        date: '2026-08-01',
        type: 'income',
      );

      final onCard = await analytics.incomeForPeriod(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        accountId: card,
      );

      expect(onCard, 0);
    });

    test('narrows income and spending by the same account, so FR-RPT-004 '
        'compares two halves of one thing', () async {
      // A chart whose expense bar is filtered and whose income bar is not
      // subtracts one account's spending from every account's income and
      // calls the difference savings.
      await insertExpense(
        categoryId: salary,
        amountCents: 8000000,
        date: '2026-08-01',
        type: 'income',
      );
      await insertExpense(
        categoryId: salary,
        amountCents: 1500000,
        date: '2026-08-02',
        accountId: card,
        type: 'income',
      );
      await insertExpense(
        categoryId: food,
        amountCents: 120000,
        date: '2026-08-03',
      );
      await insertExpense(
        categoryId: transport,
        amountCents: 500000,
        date: '2026-08-04',
        accountId: card,
      );

      final income = await analytics.incomeForPeriod(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        accountId: card,
      );
      final spending = await analytics.spendingByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        accountId: card,
      );

      expect(income, 1500000);
      expect(spending.fold(0, (sum, t) => sum + t.amountCents), 500000);
    });

    test('a transfer is not income, filtered or not (E-02)', () async {
      await db.insert('transactions', {
        'account_id': cash,
        'amount_cents': 2500000,
        'type': 'transfer',
        'transfer_direction': 'in',
        'date': '2026-08-10',
        'created_at': '2026-08-10T00:00:00Z',
        'updated_at': '2026-08-10T00:00:00Z',
      });

      final onCash = await analytics.incomeForPeriod(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        accountId: cash,
      );

      expect(onCash, 0);
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

  group('spending over time (FR-RPT-005)', () {
    test('cuts a month into daily points, earliest first', () async {
      await insertExpense(
        categoryId: food,
        amountCents: 120000,
        date: '2026-08-14',
      );
      await insertExpense(
        categoryId: food,
        amountCents: 80000,
        date: '2026-08-03',
      );
      await insertExpense(
        categoryId: food,
        amountCents: 50000,
        date: '2026-08-03',
      );

      final points = await analytics.spendingTrend(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        granularity: TrendGranularity.day,
      );

      expect(points.map((p) => p.bucket), [
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 14),
      ]);
      expect(points.first.amountCents, 130000);
      expect(points.last.amountCents, 120000);
    });

    test('cuts a year into monthly points on the first of each', () async {
      await insertExpense(categoryId: food, amountCents: 1, date: '2026-03-31');
      await insertExpense(categoryId: food, amountCents: 2, date: '2026-03-01');
      await insertExpense(categoryId: food, amountCents: 4, date: '2026-11-15');

      final points = await analytics.spendingTrend(
        from: DateTime(2026),
        to: DateTime(2026, 12, 31),
        granularity: TrendGranularity.month,
      );

      expect(
        {for (final p in points) p.bucket: p.amountCents},
        {DateTime(2026, 3): 3, DateTime(2026, 11): 4},
      );
    });

    test('is sparse: a bucket with nothing spent has no row', () async {
      await insertExpense(categoryId: food, amountCents: 1, date: '2026-08-03');

      final points = await analytics.spendingTrend(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        granularity: TrendGranularity.day,
      );

      expect(points.length, 1);
    });

    test('keeps categories apart within one bucket, largest first', () async {
      await insertExpense(
        categoryId: food,
        amountCents: 100,
        date: '2026-08-03',
      );
      await insertExpense(
        categoryId: transport,
        amountCents: 900,
        date: '2026-08-03',
      );

      final points = await analytics.spendingTrend(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        granularity: TrendGranularity.day,
      );

      expect(points.map((p) => p.name), ['Transport', 'Food']);
      expect(points.map((p) => p.categoryId), [transport, food]);
      expect(points.every((p) => p.color.isNotEmpty), isTrue);
    });

    test("a split lands on its parts, in the parent's bucket (E-04)", () async {
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

      final points = await analytics.spendingTrend(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        granularity: TrendGranularity.day,
      );

      expect(
        {for (final p in points) p.name: p.amountCents},
        {'Food': 200000, 'Transport': 100000},
      );
      expect(points.every((p) => p.bucket == DateTime(2026, 8, 5)), isTrue);
    });

    test('a transfer and an income contribute nothing (E-02)', () async {
      for (final (account, direction) in [(cash, 'out'), (card, 'in')]) {
        await db.insert('transactions', {
          'account_id': account,
          'amount_cents': 2500000,
          'type': 'transfer',
          'transfer_direction': direction,
          'date': '2026-08-10',
          'created_at': '2026-08-10T00:00:00Z',
          'updated_at': '2026-08-10T00:00:00Z',
        });
      }
      await insertExpense(
        categoryId: salary,
        amountCents: 8000000,
        date: '2026-08-01',
        type: 'income',
      );

      final points = await analytics.spendingTrend(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        granularity: TrendGranularity.day,
      );

      expect(points, isEmpty);
    });

    test('counts only the account asked for (FR-RPT-003)', () async {
      await insertExpense(
        categoryId: food,
        amountCents: 100,
        date: '2026-08-03',
        accountId: cash,
      );
      await insertExpense(
        categoryId: food,
        amountCents: 900,
        date: '2026-08-04',
        accountId: card,
      );

      final onCard = await analytics.spendingTrend(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        granularity: TrendGranularity.day,
        accountId: card,
      );
      final everywhere = await analytics.spendingTrend(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        granularity: TrendGranularity.day,
      );

      expect(onCard.single.bucket, DateTime(2026, 8, 4));
      expect(onCard.single.amountCents, 900);
      expect(everywhere.length, 2);
    });

    test(
      'adds up to what spendingByCategory says for the same query',
      () async {
        // The two statements are assembled from one fragment; this is the
        // check that they still count the same rows after either is touched.
        final parent = await insertExpense(
          categoryId: food,
          amountCents: 300000,
          date: '2026-08-05',
          isSplit: true,
        );
        await db.insert('transaction_splits', {
          'transaction_id': parent,
          'category_id': transport,
          'amount_cents': 300000,
        });
        await insertExpense(
          categoryId: food,
          amountCents: 50000,
          date: '2026-08-06',
        );
        await insertExpense(
          categoryId: food,
          amountCents: 70000,
          date: '2026-08-30',
        );

        final totals = await analytics.spendingByCategory(
          from: DateTime(2026, 8),
          to: DateTime(2026, 8, 31),
        );
        final points = await analytics.spendingTrend(
          from: DateTime(2026, 8),
          to: DateTime(2026, 8, 31),
          granularity: TrendGranularity.day,
        );

        final summed = <String, int>{};
        for (final p in points) {
          summed[p.name] = (summed[p.name] ?? 0) + p.amountCents;
        }
        expect(summed, {for (final t in totals) t.name: t.amountCents});
      },
    );
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

    test('the monthly trend of Bills is flat, as the seed shapes it', () async {
      final points = await analytics.spendingTrend(
        from: DateTime(2025, 9),
        to: end,
        granularity: TrendGranularity.month,
      );

      final bills = points.where((p) => p.name == 'Bills').toList();
      expect(bills.length, 12);
      final smallest = bills
          .map((p) => p.amountCents)
          .reduce((a, b) => a < b ? a : b);
      final largest = bills
          .map((p) => p.amountCents)
          .reduce((a, b) => a > b ? a : b);
      expect((largest - smallest) / largest, lessThan(0.15));
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
