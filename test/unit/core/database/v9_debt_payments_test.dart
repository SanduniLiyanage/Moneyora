@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/migrations/v9_debt_payments.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An existing v8 database upgrades to v9 **with its rows intact** — debts
/// open and paid, a credit card, a transaction — every debt still a debt
/// through no account, every transaction no debt's, no balance moved, and
/// the new columns' CHECK and foreign keys holding (E-47).
void main() {
  sqfliteFfiInit();

  late Database db;

  const now = '2026-10-11T00:00:00Z';

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    // Every version before v9, as 1.2.0 leaves a database.
    await db.execute(createSchemaMigrations);
    for (final version
        in schemaMigrations.keys.where((v) => v < v9SchemaVersion).toList()
          ..sort()) {
      for (final statement in schemaMigrations[version]!) {
        await db.execute(statement);
      }
      await db.insert('schema_migrations', {
        'version': version,
        'applied_at': now,
      });
    }
    await db.insert('users', {'id': 1, 'created_at': now});
    await db.insert('accounts', {
      'id': 1,
      'user_id': 1,
      'name': 'Visa',
      'icon': 'card',
      'type': 'credit_card',
      'initial_balance_cents': 0,
      'current_balance_cents': -1250000,
      'initial_balance_date': '2026-10-01',
      'credit_limit_cents': 5000000,
      'created_at': now,
    });
    for (final (id, direction, cents, paid) in [
      (1, 'owed_to_me', 100000, null),
      (2, 'i_owe', 40000, null),
      (3, 'owed_to_me', 25000, '2026-10-05'),
    ]) {
      await db.insert('debts', {
        'id': id,
        'direction': direction,
        'person': 'Nimal',
        'amount_cents': cents,
        'incurred_on': '2026-10-01',
        'paid_on': paid,
        'created_at': now,
        'updated_at': now,
      });
    }
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
      'amount_cents': 1250000,
      'type': 'expense',
      'date': '2026-10-02',
      'time': '12:58',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() => db.close());

  test('upgrades with every debt intact, each one still a debt', () async {
    await DatabaseHelper.migrate(db);

    expect(await DatabaseHelper.appliedVersions(db), contains(9));
    final debts = await db.query('debts', orderBy: 'id');
    expect([for (final d in debts) d['amount_cents']], [100000, 40000, 25000]);
    expect(
      [for (final d in debts) d['direction']],
      ['owed_to_me', 'i_owe', 'owed_to_me'],
    );
    expect([for (final d in debts) d['paid_on']], [null, null, '2026-10-05']);
    expect([for (final d in debts) d['is_payment']], [0, 0, 0]);
    expect([for (final d in debts) d['account_id']], [null, null, null]);
    expect([for (final d in debts) d['paid_account_id']], [null, null, null]);
    final transaction = (await db.query('transactions')).single;
    expect(transaction['amount_cents'], 1250000, reason: 'intact');
    expect(transaction['time'], '12:58', reason: 'intact');
    expect(transaction['debt_id'], isNull);
    final card = (await db.query('accounts')).single;
    expect(card['current_balance_cents'], -1250000, reason: 'intact');
    expect(card['credit_limit_cents'], 5000000, reason: 'intact');
  });

  group('the CHECKs', () {
    setUp(() => DatabaseHelper.migrate(db));

    test('a payment as the app writes one is accepted', () async {
      await db.update('debts', {'is_payment': 1}, where: 'id = 2');
      expect(
        (await db.query('debts', where: 'id = 2')).single['is_payment'],
        1,
      );
    });

    test('a debt names an account that exists, and a movement a debt that '
        'does', () async {
      await db.update('debts', {'account_id': 1}, where: 'id = 1');
      await expectLater(
        db.update('debts', {'account_id': 99}, where: 'id = 1'),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.update('transactions', {'debt_id': 99}),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('it is a payment or it is not', () async {
      await expectLater(
        db.update('debts', {'is_payment': 2}, where: 'id = 1'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  test('v9 is registered', () {
    expect(schemaMigrations[v9SchemaVersion], v9Statements);
    expect(latestSchemaVersion, greaterThanOrEqualTo(v9SchemaVersion));
  });
}
