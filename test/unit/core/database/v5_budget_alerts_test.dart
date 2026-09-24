@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/migrations/v2_carry_over.dart';
import 'package:moneyora/core/database/migrations/v3_receipt_scanner.dart';
import 'package:moneyora/core/database/migrations/v4_multi_currency.dart';
import 'package:moneyora/core/database/migrations/v5_budget_alerts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The test `database_helper.dart` asks for with every new version: an
/// existing v4 database upgrades to v5 **with its rows intact** — the
/// user's preferences and a plan already being tracked — and with both new
/// columns at their defaults (E-35).
void main() {
  sqfliteFfiInit();

  late Database db;

  const now = '2026-09-01T00:00:00Z';

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    // A v4 database as a Sprint 7 install left it before this version.
    await db.execute(createSchemaMigrations);
    for (final statement in [
      ...v1Statements,
      ...v2Statements,
      ...v3Statements,
      ...v4Statements,
    ]) {
      await db.execute(statement);
    }
    for (final version in [
      v1SchemaVersion,
      v2SchemaVersion,
      v3SchemaVersion,
      v4SchemaVersion,
    ]) {
      await db.insert('schema_migrations', {
        'version': version,
        'applied_at': now,
      });
    }
    await db.insert('users', {
      'id': 1,
      'theme': 'dark',
      'currency': 'USD',
      'plan_analysis_months': 12,
      'created_at': now,
    });
    await db.insert('categories', {
      'id': 1,
      'user_id': 1,
      'name': 'Food',
      'type': 'expense',
      'icon': 'restaurant',
      'color': '#FF7043',
    });
    await db.insert('money_plans', {
      'id': 1,
      'user_id': 1,
      'name': 'September',
      'period_type': 'month',
      'start_date': '2026-09-01',
      'end_date': '2026-09-30',
      'total_budget_cents': 3000000,
      'is_active': 1,
      'created_at': now,
    });
    // Already past 80% before this version existed: nothing was announced,
    // and the column says so.
    await db.insert('plan_allocations', {
      'id': 1,
      'plan_id': 1,
      'category_id': 1,
      'allocated_amount_cents': 3000000,
      'spent_amount_cents': 2700000,
      'carry_over_cents': 0,
      'confidence_level': 'medium',
      'is_user_modified': 1,
    });
  });

  tearDown(() => db.close());

  test('upgrades with every row intact and both columns at their '
      'defaults', () async {
    await DatabaseHelper.migrate(db);

    expect(await DatabaseHelper.appliedVersions(db), {1, 2, 3, 4, 5});

    final user = (await db.query('users')).single;
    expect(user['theme'], 'dark', reason: 'intact');
    expect(user['currency'], 'USD', reason: 'intact');
    expect(user['plan_analysis_months'], 12, reason: 'intact');
    expect(user['budget_alerts_enabled'], 0, reason: 'off until chosen');

    final allocation = (await db.query('plan_allocations')).single;
    expect(allocation['spent_amount_cents'], 2700000, reason: 'intact');
    expect(allocation['is_user_modified'], 1, reason: 'intact');
    expect(allocation['alerted_level'], 0, reason: 'nothing announced yet');
  });

  test('is additive: v4 has neither column, v5 has both', () async {
    Future<Set<String>> columns(String table) async => {
      for (final row in await db.rawQuery('PRAGMA table_info($table)'))
        row['name']! as String,
    };
    expect(await columns('users'), isNot(contains('budget_alerts_enabled')));
    expect(await columns('plan_allocations'), isNot(contains('alerted_level')));

    await DatabaseHelper.migrate(db);

    expect(await columns('users'), contains('budget_alerts_enabled'));
    expect(await columns('plan_allocations'), contains('alerted_level'));
  });

  group('the CHECKs', () {
    setUp(() => DatabaseHelper.migrate(db));

    test('alerted_level holds only the thresholds it names', () async {
      for (final level in [0, 80, 100]) {
        await db.update('plan_allocations', {'alerted_level': level});
      }
      for (final level in [-1, 50, 101]) {
        expect(
          () => db.update('plan_allocations', {'alerted_level': level}),
          throwsA(isA<DatabaseException>()),
          reason: '$level',
        );
      }
    });

    test('budget_alerts_enabled is a flag', () async {
      await db.update('users', {'budget_alerts_enabled': 1});
      expect(
        () => db.update('users', {'budget_alerts_enabled': 2}),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('neither column accepts null', () async {
      expect(
        () => db.update('plan_allocations', {'alerted_level': null}),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        () => db.update('users', {'budget_alerts_enabled': null}),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  test('v5 is the latest version', () {
    expect(schemaMigrations[v5SchemaVersion], v5Statements);
    expect(latestSchemaVersion, v5SchemaVersion);
  });
}
