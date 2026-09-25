@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/migrations/v2_carry_over.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The test `database_helper.dart` asks for with every new version: an
/// existing v1 database upgrades to v2 **with its rows intact**.
void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    // A v1 database as a Sprint 4 install left it: the v1 statements and a
    // schema_migrations row saying so, nothing newer.
    await db.execute(createSchemaMigrations);
    for (final statement in v1Statements) {
      await db.execute(statement);
    }
    await db.insert('schema_migrations', {
      'version': v1SchemaVersion,
      'applied_at': '2026-09-01T00:00:00Z',
    });
    await db.insert('users', {'id': 1, 'created_at': '2026-09-01T00:00:00Z'});
    await db.insert('categories', {
      'id': 1,
      'user_id': 1,
      'name': 'Food',
      'icon': 'basket',
      'color': '#7b5ea7',
      'type': 'expense',
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
      'created_at': '2026-09-01T00:00:00Z',
    });
    await db.insert('plan_allocations', {
      'plan_id': 1,
      'category_id': 1,
      'allocated_amount_cents': 3000000,
      'spent_amount_cents': 1234500,
      'confidence_level': 'high',
    });
  });

  tearDown(() => db.close());

  test('adds carry_over_cents at zero and keeps every row', () async {
    await DatabaseHelper.migrate(db);

    expect(await DatabaseHelper.appliedVersions(db), {1, 2, 3, 4, 5, 6});
    final rows = await db.query('plan_allocations');
    expect(rows, hasLength(1));
    expect(rows.single['spent_amount_cents'], 1234500, reason: 'intact');
    expect(rows.single['carry_over_cents'], 0);
  });

  test('is additive: v1 has no such column, v2 does', () async {
    Future<Set<String>> columns() async => {
      for (final row in await db.rawQuery(
        'PRAGMA table_info(plan_allocations)',
      ))
        row['name']! as String,
    };
    expect(await columns(), isNot(contains('carry_over_cents')));

    await DatabaseHelper.migrate(db);

    expect(await columns(), contains('carry_over_cents'));
  });

  test('refuses a negative carry-over', () async {
    await DatabaseHelper.migrate(db);

    expect(
      () => db.update('plan_allocations', {'carry_over_cents': -1}),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('v2 is a version, no longer the latest', () {
    expect(schemaMigrations[v2SchemaVersion], v2Statements);
    expect(latestSchemaVersion, greaterThan(v2SchemaVersion));
  });
}
