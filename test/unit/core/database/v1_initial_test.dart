@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The schema lives in Dart string constants, so the compiler never sees the
/// SQL. These tests are the only thing standing between a typo and a migration
/// that fails on a user's device with their data already in it.
///
/// The CHECK-constraint tests matter more than they look. Each one corresponds
/// to an errata resolution, and a constraint that silently fails to fire is
/// worse than no constraint at all — it reads as protection while providing
/// none.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late Database db;

  const now = '2026-09-01T00:00:00Z';

  /// Opens an in-memory database with the v1 schema applied.
  Future<Database> openSchema() async {
    final database = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: v1SchemaVersion,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          final batch = d.batch();
          for (final statement in v1Statements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        },
      ),
    );
    return database;
  }

  /// Inserts the minimum rows every constraint test needs.
  Future<void> seedFixtures(Database d) async {
    await d.insert('users', {'id': 1, 'created_at': now});
    for (final (id, name, icon) in [(1, 'Cash', 'cash'), (2, 'Card', 'visa')]) {
      await d.insert('accounts', {
        'id': id,
        'user_id': 1,
        'name': name,
        'icon': icon,
        'initial_balance_date': '2026-09-01',
        'created_at': now,
      });
    }
    await d.insert('categories', {
      'id': 1,
      'user_id': 1,
      'name': 'Food',
      'icon': 'basket',
      'color': '#C62828',
      'type': 'expense',
    });
  }

  /// A transaction row with sensible defaults, overridable per test.
  Map<String, Object?> tx({
    int accountId = 1,
    int? categoryId = 1,
    int amountCents = 12550,
    String type = 'expense',
    String? transferDirection,
  }) => {
    'account_id': accountId,
    'category_id': categoryId,
    'amount_cents': amountCents,
    'type': type,
    'transfer_direction': transferDirection,
    'date': '2026-09-01',
    'created_at': now,
    'updated_at': now,
  };

  setUp(() async {
    db = await openSchema();
    await seedFixtures(db);
  });

  tearDown(() async => db.close());

  group('schema shape', () {
    test('creates every table the baselines and errata require', () async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      );
      final names = rows.map((r) => r['name']! as String).toSet();

      expect(
        names,
        containsAll(<String>{
          'schema_migrations',
          'users',
          'accounts',
          'categories',
          'transactions',
          'transfers',
          'transaction_splits', // E-04
          'recurring_rules', // E-03
          'money_plans',
          'plan_allocations',
          'receipt_scans',
          'receipt_items',
          'keyword_dictionary',
        }),
      );
    });

    test(
      'creates every index, so no query falls back to a table scan',
      () async {
        final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE 'idx_%'",
        );
        expect(rows, hasLength(11));
      },
    );

    test('stores money as INTEGER, never REAL (E-06)', () async {
      // Every column whose name ends in _cents must be INTEGER. A REAL here
      // would reintroduce the drift the whole convention exists to prevent,
      // and it would do so silently.
      for (final table in ['transactions', 'accounts', 'plan_allocations']) {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        final money = columns.where(
          (c) => (c['name']! as String).endsWith('_cents'),
        );
        expect(money, isNotEmpty, reason: '$table should hold money columns');
        for (final column in money) {
          expect(
            column['type'],
            'INTEGER',
            reason: '$table.${column['name']} must be INTEGER minor units',
          );
        }
      }
    });
  });

  group('transaction constraints', () {
    test('accepts a well-formed expense', () async {
      await expectLater(db.insert('transactions', tx()), completes);
    });

    test('rejects a negative or zero amount', () async {
      await expectLater(
        db.insert('transactions', tx(amountCents: -500)),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('transactions', tx(amountCents: 0)),
        throwsA(isA<DatabaseException>()),
      );
    });

    test(
      'requires a category on anything that is not a transfer (E-17)',
      () async {
        await expectLater(
          db.insert('transactions', tx(categoryId: null)),
          throwsA(isA<DatabaseException>()),
        );
      },
    );

    test('forbids a category on a transfer (E-17)', () async {
      // Without this, inserting a transfer would need a sentinel category,
      // which would then appear in the donut chart as though it were spending.
      await expectLater(
        db.insert(
          'transactions',
          tx(type: 'transfer', transferDirection: 'out'),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('requires a direction on a transfer (E-16)', () async {
      // amount_cents is always positive and both halves say type='transfer',
      // so without a direction nothing on the row says which way money moved.
      await expectLater(
        db.insert('transactions', tx(type: 'transfer', categoryId: null)),
        throwsA(isA<DatabaseException>()),
      );
    });

    test(
      'forbids a direction on anything that is not a transfer (E-16)',
      () async {
        await expectLater(
          db.insert('transactions', tx(transferDirection: 'out')),
          throwsA(isA<DatabaseException>()),
        );
      },
    );

    test('accepts both halves of a transfer', () async {
      await expectLater(
        db.insert(
          'transactions',
          tx(categoryId: null, type: 'transfer', transferDirection: 'out'),
        ),
        completes,
      );
      await expectLater(
        db.insert(
          'transactions',
          tx(
            accountId: 2,
            categoryId: null,
            type: 'transfer',
            transferDirection: 'in',
          ),
        ),
        completes,
      );
    });
  });

  group('recurring rules (E-03)', () {
    Map<String, Object?> rule({
      String frequency = 'monthly',
      int? dayOfMonth = 15,
      int? intervalDays,
    }) => {
      'frequency': frequency,
      'day_of_month': dayOfMonth,
      'interval_days': intervalDays,
      'start_date': '2026-09-01',
      'next_due_date': '2026-10-01',
    };

    test('rejects a day_of_month above 28', () async {
      // A rule set for the 31st would silently skip February. Capping removes
      // the edge case instead of asking every caller to remember it.
      await expectLater(
        db.insert('recurring_rules', rule(dayOfMonth: 31)),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('accepts day_of_month 28', () async {
      await expectLater(
        db.insert('recurring_rules', rule(dayOfMonth: 28)),
        completes,
      );
    });

    test('requires interval_days when frequency is custom_days', () async {
      await expectLater(
        db.insert('recurring_rules', rule(frequency: 'custom_days')),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert(
          'recurring_rules',
          rule(frequency: 'custom_days', dayOfMonth: null, intervalDays: 10),
        ),
        completes,
      );
    });
  });

  group('transfers header (E-15)', () {
    test(
      'refuses a transfer whose source and destination are the same',
      () async {
        final fromId = await db.insert(
          'transactions',
          tx(categoryId: null, type: 'transfer', transferDirection: 'out'),
        );
        final toId = await db.insert(
          'transactions',
          tx(
            accountId: 2,
            categoryId: null,
            type: 'transfer',
            transferDirection: 'in',
          ),
        );

        await expectLater(
          db.insert('transfers', {
            'from_account_id': 1,
            'to_account_id': 1,
            'amount_cents': 800000,
            'date': '2026-09-01',
            'from_tx_id': fromId,
            'to_tx_id': toId,
            'created_at': now,
          }),
          throwsA(isA<DatabaseException>()),
        );
      },
    );
  });

  group('money plans', () {
    test('refuses a plan that ends before it starts', () async {
      await expectLater(
        db.insert('money_plans', {
          'user_id': 1,
          'name': 'Backwards',
          'period_type': 'month',
          'start_date': '2026-09-30',
          'end_date': '2026-09-01',
          'total_budget_cents': 100000,
          'created_at': now,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('deleting a plan removes its allocations', () async {
      final planId = await db.insert('money_plans', {
        'user_id': 1,
        'name': 'September',
        'period_type': 'month',
        'start_date': '2026-09-01',
        'end_date': '2026-09-30',
        'total_budget_cents': 5000000,
        'created_at': now,
      });
      await db.insert('plan_allocations', {
        'plan_id': planId,
        'category_id': 1,
        'allocated_amount_cents': 2000000,
        'confidence_level': 'high',
        'expense_class': 'variable',
      });

      await db.delete('money_plans', where: 'id = ?', whereArgs: [planId]);

      final orphans = await db.query('plan_allocations');
      expect(orphans, isEmpty, reason: 'ON DELETE CASCADE should have fired');
    });
  });

  group('split expenses (E-04)', () {
    test('deleting the parent transaction removes its splits', () async {
      final txId = await db.insert('transactions', tx());
      await db.insert('transaction_splits', {
        'transaction_id': txId,
        'category_id': 1,
        'amount_cents': 5000,
      });

      await db.delete('transactions', where: 'id = ?', whereArgs: [txId]);

      expect(await db.query('transaction_splits'), isEmpty);
    });

    test('rejects a split of zero or less', () async {
      final txId = await db.insert('transactions', tx());
      await expectLater(
        db.insert('transaction_splits', {
          'transaction_id': txId,
          'category_id': 1,
          'amount_cents': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
