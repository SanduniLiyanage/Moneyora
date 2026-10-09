@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/migrations/v8_credit_cards.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An existing v7 database upgrades to v8 **with its rows intact** — a
/// credit card owing money — and the four terms columns null, with CHECKs
/// that hold (E-43).
void main() {
  sqfliteFfiInit();

  late Database db;

  const now = '2026-10-01T00:00:00Z';

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    // Every version before v8, as the debts release leaves a database.
    await db.execute(createSchemaMigrations);
    for (final version
        in schemaMigrations.keys.where((v) => v < v8SchemaVersion).toList()
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
      'initial_balance_cents': -450000,
      'current_balance_cents': -520000,
      'initial_balance_date': '2026-09-01',
      'created_at': now,
    });
  });

  tearDown(() => db.close());

  test('upgrades with the card intact and its terms empty', () async {
    await DatabaseHelper.migrate(db);

    expect(await DatabaseHelper.appliedVersions(db), contains(8));
    final card = (await db.query('accounts')).single;
    expect(card['current_balance_cents'], -520000, reason: 'intact');
    expect(card['type'], 'credit_card', reason: 'intact');
    for (final column in [
      'credit_limit_cents',
      'statement_day',
      'payment_due_day',
      'apr_basis_points',
    ]) {
      expect(card.containsKey(column), isTrue, reason: column);
      expect(card[column], isNull, reason: column);
    }
  });

  group('the CHECKs', () {
    setUp(() => DatabaseHelper.migrate(db));

    Future<void> refused(String column, Object value) => expectLater(
      db.update('accounts', {column: value}),
      throwsA(isA<DatabaseException>()),
      reason: '$column = $value',
    );

    test('accepts terms as the form writes them', () async {
      await db.update('accounts', {
        'credit_limit_cents': 50000000,
        'statement_day': 31,
        'payment_due_day': 1,
        'apr_basis_points': 2450,
      });
      expect((await db.query('accounts')).single['apr_basis_points'], 2450);
    });

    test('a limit is above zero', () => refused('credit_limit_cents', 0));

    test('each day is in a month', () async {
      await refused('statement_day', 0);
      await refused('statement_day', 32);
      await refused('payment_due_day', 0);
      await refused('payment_due_day', 32);
    });

    test('the rate is 0% to 100%', () async {
      await refused('apr_basis_points', -1);
      await refused('apr_basis_points', 10001);
    });
  });

  test('v8 is registered', () {
    expect(schemaMigrations[v8SchemaVersion], v8Statements);
    expect(latestSchemaVersion, greaterThanOrEqualTo(v8SchemaVersion));
  });
}
