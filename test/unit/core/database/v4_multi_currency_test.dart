@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/migrations/v2_carry_over.dart';
import 'package:moneyora/core/database/migrations/v3_receipt_scanner.dart';
import 'package:moneyora/core/database/migrations/v4_multi_currency.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The test `database_helper.dart` asks for with every new version: an
/// existing v3 database upgrades to v4 **with its rows intact** — and, for
/// this version, with the new transfer column backfilled on every row that
/// predates it (E-34).
void main() {
  sqfliteFfiInit();

  late Database db;

  const now = '2026-09-01T00:00:00Z';

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    // A v3 database as a Sprint 6 install left it.
    await db.execute(createSchemaMigrations);
    for (final statement in [
      ...v1Statements,
      ...v2Statements,
      ...v3Statements,
    ]) {
      await db.execute(statement);
    }
    for (final version in [v1SchemaVersion, v2SchemaVersion, v3SchemaVersion]) {
      await db.insert('schema_migrations', {
        'version': version,
        'applied_at': now,
      });
    }
    await db.insert('users', {'id': 1, 'created_at': now});
    for (final (id, name) in [(1, 'Cash'), (2, 'Bank')]) {
      await db.insert('accounts', {
        'id': id,
        'user_id': 1,
        'name': name,
        'icon': 'wallet',
        'initial_balance_date': '2026-01-01',
        'created_at': now,
      });
    }
    // One transfer, written the way the v1–v3 datasource wrote it: both
    // halves, then the header, one amount everywhere.
    for (final (id, account, direction) in [(1, 1, 'out'), (2, 2, 'in')]) {
      await db.insert('transactions', {
        'id': id,
        'account_id': account,
        'amount_cents': 250000,
        'type': 'transfer',
        'transfer_direction': direction,
        'date': '2026-08-15',
        'created_at': now,
        'updated_at': now,
      });
    }
    await db.insert('transfers', {
      'id': 1,
      'from_account_id': 1,
      'to_account_id': 2,
      'amount_cents': 250000,
      'date': '2026-08-15',
      'from_tx_id': 1,
      'to_tx_id': 2,
      'created_at': now,
    });
  });

  tearDown(() => db.close());

  test('backfills credited_amount_cents from amount_cents, rows intact', () async {
    await DatabaseHelper.migrate(db);

    expect(await DatabaseHelper.appliedVersions(db), {1, 2, 3, 4});
    final rows = await db.query('transfers');
    expect(rows, hasLength(1));
    expect(rows.single['amount_cents'], 250000, reason: 'intact');
    // E-34: nullable in the DDL, never null after the migration.
    expect(rows.single['credited_amount_cents'], 250000);
  });

  test('is additive: v3 has no such column, v4 does', () async {
    Future<Set<String>> columns() async => {
      for (final row in await db.rawQuery('PRAGMA table_info(transfers)'))
        row['name']! as String,
    };
    expect(await columns(), isNot(contains('credited_amount_cents')));

    await DatabaseHelper.migrate(db);

    expect(await columns(), contains('credited_amount_cents'));
  });

  test('refuses a credited amount of nothing', () async {
    await DatabaseHelper.migrate(db);

    expect(
      () => db.update('transfers', {'credited_amount_cents': 0}),
      throwsA(isA<DatabaseException>()),
    );
  });

  group('exchange_rates', () {
    setUp(() => DatabaseHelper.migrate(db));

    test('exists, empty', () async {
      expect(await db.query('exchange_rates'), isEmpty);
    });

    test('holds one rate per ordered pair', () async {
      await db.insert('exchange_rates', {
        'from_currency': 'USD',
        'to_currency': 'LKR',
        'rate_micros': 300250000,
        'updated_at': now,
      });

      expect(
        () => db.insert('exchange_rates', {
          'from_currency': 'USD',
          'to_currency': 'LKR',
          'rate_micros': 1,
          'updated_at': now,
        }),
        throwsA(isA<DatabaseException>()),
      );
      // The reverse pair is a different row, not a conflict.
      await db.insert('exchange_rates', {
        'from_currency': 'LKR',
        'to_currency': 'USD',
        'rate_micros': 3331,
        'updated_at': now,
      });
      expect(await db.query('exchange_rates'), hasLength(2));
    });

    test('refuses a rate of nothing and a currency against itself', () async {
      expect(
        () => db.insert('exchange_rates', {
          'from_currency': 'USD',
          'to_currency': 'LKR',
          'rate_micros': 0,
          'updated_at': now,
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        () => db.insert('exchange_rates', {
          'from_currency': 'LKR',
          'to_currency': 'LKR',
          'rate_micros': 1000000,
          'updated_at': now,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  test('v4 is the latest version', () {
    expect(schemaMigrations[v4SchemaVersion], v4Statements);
    expect(latestSchemaVersion, v4SchemaVersion);
  });
}
