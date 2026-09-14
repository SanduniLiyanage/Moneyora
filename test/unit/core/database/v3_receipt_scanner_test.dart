@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/migrations/v2_carry_over.dart';
import 'package:moneyora/core/database/migrations/v3_receipt_scanner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The test `database_helper.dart` asks for with every new version: an
/// existing v2 database upgrades to v3 **with its rows intact** — and, for
/// the one table v3 recreates, the proof of what the recreation buys.
void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    // A v2 database as a Sprint 5 install left it.
    await db.execute(createSchemaMigrations);
    for (final statement in [...v1Statements, ...v2Statements]) {
      await db.execute(statement);
    }
    for (final version in [v1SchemaVersion, v2SchemaVersion]) {
      await db.insert('schema_migrations', {
        'version': version,
        'applied_at': '2026-09-01T00:00:00Z',
      });
    }
    await db.insert('users', {'id': 1, 'created_at': '2026-09-01T00:00:00Z'});
    await db.insert('categories', {
      'id': 1,
      'user_id': 1,
      'name': 'Health',
      'icon': 'thermometer',
      'color': '#e87ba4',
      'type': 'expense',
    });
    await db.insert('receipt_scans', {
      'id': 1,
      'user_id': 1,
      'image_path': 'receipts/1.enc',
      'merchant_name': 'HEALTHGUARD PHARMACY',
      'total_amount_cents': 70500,
      'created_at': '2026-09-01T00:00:00Z',
    });
  });

  tearDown(() => db.close());

  test('adds receipt_number, null, and keeps every scan', () async {
    await DatabaseHelper.migrate(db);

    expect(await DatabaseHelper.appliedVersions(db), {1, 2, 3});
    final rows = await db.query('receipt_scans');
    expect(rows, hasLength(1));
    expect(rows.single['total_amount_cents'], 70500, reason: 'intact');
    expect(rows.single['receipt_number'], isNull);
    await db.update('receipt_scans', {'receipt_number': 'HG-00917'});
    expect(
      (await db.query('receipt_scans')).single['receipt_number'],
      'HG-00917',
    );
  });

  test('a keyword goes with its category once v3 has run', () async {
    // Before v3 the constraint refuses; the DBD said cascade.
    await db.insert('keyword_dictionary', {
      'keyword': 'panadol',
      'category_id': 1,
    });
    expect(
      () => db.delete('categories', where: 'id = 1'),
      throwsA(isA<DatabaseException>()),
    );
    await db.delete('keyword_dictionary');

    await DatabaseHelper.migrate(db);

    await db.insert('keyword_dictionary', {
      'keyword': 'panadol',
      'category_id': 1,
    });
    await db.delete('categories', where: 'id = 1');
    expect(await db.query('keyword_dictionary'), isEmpty);
  });

  test('the recreated table keeps every v1 column and constraint', () async {
    Future<Map<String, String>> columns() async => {
      for (final row in await db.rawQuery(
        'PRAGMA table_info(keyword_dictionary)',
      ))
        row['name']! as String: row['type']! as String,
    };
    final before = await columns();

    await DatabaseHelper.migrate(db);

    expect(await columns(), before);
    expect(
      () => db.insert('keyword_dictionary', {
        'keyword': 'x',
        'category_id': 1,
        'match_type': 'regex',
      }),
      throwsA(isA<DatabaseException>()),
      reason: 'the match_type check survives',
    );
    await db.insert('keyword_dictionary', {'keyword': 'x', 'category_id': 1});
    expect(
      () => db.insert('keyword_dictionary', {'keyword': 'x', 'category_id': 1}),
      throwsA(isA<DatabaseException>()),
      reason: 'the (keyword, category_id) unique constraint survives',
    );
    final indexes = await db.rawQuery('PRAGMA index_list(keyword_dictionary)');
    expect(indexes.map((i) => i['name']), contains('idx_keyword_dict_keyword'));
  });

  test('v3 is the latest version', () {
    expect(latestSchemaVersion, v3SchemaVersion);
  });
}
