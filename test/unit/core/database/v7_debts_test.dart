@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/migrations/v2_carry_over.dart';
import 'package:moneyora/core/database/migrations/v3_receipt_scanner.dart';
import 'package:moneyora/core/database/migrations/v4_multi_currency.dart';
import 'package:moneyora/core/database/migrations/v5_budget_alerts.dart';
import 'package:moneyora/core/database/migrations/v6_recurring_reminders.dart';
import 'package:moneyora/core/database/migrations/v7_debts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An existing v6 database upgrades to v7 **with its rows intact** — an
/// account and a transaction in it — and gains an empty `debts` table
/// whose CHECKs hold (E-42).
void main() {
  sqfliteFfiInit();

  late Database db;

  const now = '2026-10-01T00:00:00Z';

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    // A v6 database as 1.1.0 left it.
    await db.execute(createSchemaMigrations);
    for (final statement in [
      ...v1Statements,
      ...v2Statements,
      ...v3Statements,
      ...v4Statements,
      ...v5Statements,
      ...v6Statements,
    ]) {
      await db.execute(statement);
    }
    for (final version in [
      v1SchemaVersion,
      v2SchemaVersion,
      v3SchemaVersion,
      v4SchemaVersion,
      v5SchemaVersion,
      v6SchemaVersion,
    ]) {
      await db.insert('schema_migrations', {
        'version': version,
        'applied_at': now,
      });
    }
    await db.insert('users', {'id': 1, 'created_at': now});
    await db.insert('accounts', {
      'id': 1,
      'user_id': 1,
      'name': 'Cash',
      'icon': 'wallet',
      'initial_balance_cents': 500000,
      'current_balance_cents': 450000,
      'initial_balance_date': '2026-09-01',
      'created_at': now,
    });
    await db.insert('categories', {
      'id': 1,
      'user_id': 1,
      'name': 'Food',
      'type': 'expense',
      'icon': 'basket',
      'color': '#C62828',
    });
    await db.insert('transactions', {
      'id': 1,
      'account_id': 1,
      'category_id': 1,
      'amount_cents': 50000,
      'type': 'expense',
      'date': '2026-09-02',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() => db.close());

  Map<String, Object?> debt([Map<String, Object?> overrides = const {}]) => {
    'direction': 'owed_to_me',
    'person': 'Nimal',
    'amount_cents': 250000,
    'incurred_on': '2026-10-01',
    'created_at': now,
    'updated_at': now,
    ...overrides,
  };

  test('upgrades with every row intact and an empty debts table', () async {
    await DatabaseHelper.migrate(db);

    expect(await DatabaseHelper.appliedVersions(db), contains(7));
    final account = (await db.query('accounts')).single;
    expect(account['current_balance_cents'], 450000, reason: 'intact');
    expect(account['initial_balance_cents'], 500000, reason: 'intact');
    expect((await db.query('transactions')).single['amount_cents'], 50000);
    expect(await db.query('debts'), isEmpty);
  });

  group('the CHECKs', () {
    setUp(() => DatabaseHelper.migrate(db));

    Future<void> refused(Map<String, Object?> overrides) => expectLater(
      db.insert('debts', debt(overrides)),
      throwsA(isA<DatabaseException>()),
      reason: '$overrides',
    );

    test('a debt as the app writes one is accepted', () async {
      await db.insert('debts', debt());
      await db.insert('debts', debt({'direction': 'i_owe', 'due_on': null}));
      expect(await db.query('debts'), hasLength(2));
    });

    test('the direction is one of two', () => refused({'direction': 'lent'}));

    test('the amount is above zero', () async {
      await refused({'amount_cents': 0});
      await refused({'amount_cents': -100});
    });

    test('there is someone', () async {
      await refused({'person': '   '});
      await refused({'person': null});
    });
  });

  test('v7 is registered', () {
    expect(schemaMigrations[v7SchemaVersion], v7Statements);
    expect(latestSchemaVersion, greaterThanOrEqualTo(v7SchemaVersion));
  });
}
