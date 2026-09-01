@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/encryption_key_store.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/dev_seed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// These tests assert the *shape* of the generated data, not merely that it
/// exists. That is the whole point of the fixture: in Sprint 5 the Money Plan
/// classifier will be asserted against these same shapes, so if the generator
/// silently stops producing a fixed-cost series or a rising trend, the
/// classifier's tests would pass while testing nothing.
void main() {
  sqfliteFfiInit();

  late DatabaseHelper helper;
  late Database db;

  // Fixed so the arithmetic below is reproducible. A generator whose output
  // moves per run cannot be an oracle.
  final endDate = DateTime(2026, 9, 1);

  setUp(() async {
    helper = DatabaseHelper(
      dbFactory: databaseFactoryFfi,
      keyStore: InMemoryKeyStore(),
      databaseName: inMemoryDatabasePath,
    );
    db = await helper.database;
    await applyDefaultSeed(db);
  });

  tearDown(() async => helper.close());

  /// Amounts, in cents, for one category.
  Future<List<int>> amountsFor(String category) async {
    final rows = await db.rawQuery(
      'SELECT t.amount_cents FROM transactions t '
      'JOIN categories c ON c.id = t.category_id WHERE c.name = ?',
      [category],
    );
    return rows.map((r) => r['amount_cents']! as int).toList();
  }

  double mean(List<int> xs) => xs.reduce((a, b) => a + b) / xs.length;

  /// Sample standard deviation, n-1 — the same estimator E-05 specifies for
  /// the plan engine, so the numbers here mean what they will mean there.
  double stdDev(List<int> xs) {
    final m = mean(xs);
    final sumSq = xs.fold<double>(0, (acc, x) => acc + pow(x - m, 2));
    return sqrt(sumSq / (xs.length - 1));
  }

  group('default seed', () {
    test(
      'creates the 15 expense and 3 income categories the SRS names',
      () async {
        final expense = await db.query(
          'categories',
          where: 'type = ?',
          whereArgs: ['expense'],
        );
        final income = await db.query(
          'categories',
          where: 'type = ?',
          whereArgs: ['income'],
        );

        expect(expense, hasLength(15)); // FR-EXP-003
        expect(income, hasLength(3)); // FR-INC-002
        expect(
          expense.map((c) => c['name']),
          containsAll(['Bills', 'Food', 'Taxi', 'Toiletry', 'Transport']),
        );
      },
    );

    test('gives every expense category a distinct colour', () async {
      // Two categories sharing a colour is indistinguishable from a bug in the
      // donut chart, and impossible to notice by reading the list.
      final colors = defaultExpenseCategories.map((c) => c.colorLight).toList();
      expect(colors.toSet(), hasLength(colors.length));

      final dark = defaultExpenseCategories.map((c) => c.colorDark).toList();
      expect(dark.toSet(), hasLength(dark.length));
    });

    test('creates one account to start with', () async {
      final accounts = await db.query('accounts');
      expect(accounts, hasLength(1));
      expect(accounts.first['name'], 'Cash');
    });
  });

  group('generated history', () {
    setUp(() async => DevSeed.populate(db, endDate: endDate));

    test('produces a substantial history across 24 months', () async {
      final rows = await db.query('transactions');
      expect(rows.length, greaterThan(500));
    });

    test(
      'Bills is a fixed cost — CV below the 0.15 classifier threshold',
      () async {
        // SRS 7.1 classifies Fixed as coefficient of variation < 0.15. If this
        // fixture drifted above it, every "classifier says Fixed" test in
        // Sprint 5 would be asserting against data that is not actually fixed.
        final amounts = await amountsFor('Bills');
        expect(amounts.length, greaterThanOrEqualTo(23));

        final cv = stdDev(amounts) / mean(amounts);
        expect(cv, lessThan(0.15), reason: 'CV was $cv');
      },
    );

    test('Food is variable — CV well above the fixed threshold', () async {
      final amounts = await amountsFor('Food');
      expect(amounts.length, greaterThan(300));

      final cv = stdDev(amounts) / mean(amounts);
      expect(cv, greaterThan(0.3), reason: 'CV was $cv');
    });

    test('Gifts spikes in April and December', () async {
      final rows = await db.rawQuery(
        "SELECT strftime('%m', t.date) AS m, SUM(t.amount_cents) AS total "
        'FROM transactions t JOIN categories c ON c.id = t.category_id '
        "WHERE c.name = 'Gifts' GROUP BY m",
      );
      final byMonth = {
        for (final r in rows) r['m']! as String: r['total']! as int,
      };

      final spikes = [byMonth['04'] ?? 0, byMonth['12'] ?? 0];
      final quiet = byMonth.entries
          .where((e) => e.key != '04' && e.key != '12')
          .map((e) => e.value)
          .toList();

      for (final spike in spikes) {
        expect(
          spike,
          greaterThan(mean(quiet) * 3),
          reason: 'a seasonal spike should dwarf a quiet month',
        );
      }
    });

    test('Car trends upward across the span', () async {
      // The plan engine adds an 8% buffer when it detects a rising trend
      // (FR-PLN-007). This fixture is what proves the detector fires.
      final rows = await db.rawQuery(
        "SELECT strftime('%Y-%m', t.date) AS m, AVG(t.amount_cents) AS avg "
        'FROM transactions t JOIN categories c ON c.id = t.category_id '
        "WHERE c.name = 'Car' GROUP BY m ORDER BY m",
      );
      final monthly = rows.map((r) => (r['avg']! as num).toDouble()).toList();

      expect(monthly.length, greaterThanOrEqualTo(12));
      expect(
        monthly.last,
        greaterThan(monthly.first * 2),
        reason: '8% a month compounds to well over double across two years',
      );
    });

    test('Pets is sparse — three transactions, which must score LOW', () async {
      // SRS Appendix C rates insufficient history as the highest-likelihood
      // risk on the project (R6). This is the fixture that lets the confidence
      // scorer be tested against it rather than hoped about.
      final amounts = await amountsFor('Pets');
      expect(amounts, hasLength(3));
    });

    test(
      'never writes a transfer, so the analytics exclusion is untested here',
      () async {
        // Stated explicitly because E-02 warns that transfers double-count in
        // analytics. If this fixture ever grows transfers, every aggregate
        // assertion above needs revisiting.
        final transfers = await db.query(
          'transactions',
          where: 'type = ?',
          whereArgs: ['transfer'],
        );
        expect(transfers, isEmpty);
      },
    );
  });

  group('determinism', () {
    test('the same seed produces byte-identical history', () async {
      final first = await DevSeed.populate(db, endDate: endDate);
      final firstRows = await db.query('transactions', orderBy: 'id');

      await db.delete('transactions');
      final second = await DevSeed.populate(db, endDate: endDate);
      final secondRows = await db.query('transactions', orderBy: 'id');

      expect(second, first);
      expect(
        secondRows.map((r) => r['amount_cents']).toList(),
        firstRows.map((r) => r['amount_cents']).toList(),
        reason: 'a non-reproducible fixture cannot be a test oracle',
      );
    });

    test('a different seed produces different history', () async {
      await DevSeed.populate(db, endDate: endDate);
      final a = await amountsFor('Food');

      await db.delete('transactions');
      await DevSeed.populate(db, endDate: endDate, randomSeed: 7);
      final b = await amountsFor('Food');

      expect(a, isNot(b));
    });
  });
}
