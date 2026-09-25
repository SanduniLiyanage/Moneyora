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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An existing v5 database upgrades to v6 **with its rows intact** — the
/// user's preferences and a recurring rule already posting — and with the
/// three reminder columns at their defaults (E-37).
void main() {
  sqfliteFfiInit();

  late Database db;

  const now = '2026-09-01T00:00:00Z';

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    // A v5 database as PR #111 onward left it.
    await db.execute(createSchemaMigrations);
    for (final statement in [
      ...v1Statements,
      ...v2Statements,
      ...v3Statements,
      ...v4Statements,
      ...v5Statements,
    ]) {
      await db.execute(statement);
    }
    for (final version in [
      v1SchemaVersion,
      v2SchemaVersion,
      v3SchemaVersion,
      v4SchemaVersion,
      v5SchemaVersion,
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
      'budget_alerts_enabled': 1,
      'created_at': now,
    });
    await db.insert('recurring_rules', {
      'id': 1,
      'frequency': 'monthly',
      'day_of_month': 5,
      'start_date': '2026-08-05',
      'next_due_date': '2026-10-05',
    });
  });

  tearDown(() => db.close());

  test(
    'upgrades with every row intact and the columns at their defaults',
    () async {
      await DatabaseHelper.migrate(db);

      expect(await DatabaseHelper.appliedVersions(db), {1, 2, 3, 4, 5, 6});

      final user = (await db.query('users')).single;
      expect(user['theme'], 'dark', reason: 'intact');
      expect(user['currency'], 'USD', reason: 'intact');
      expect(user['budget_alerts_enabled'], 1, reason: 'intact');
      expect(
        user['recurring_reminders_enabled'],
        0,
        reason: 'off until chosen',
      );
      expect(
        user['recurring_reminder_days_before'],
        1,
        reason: 'the day before',
      );
      expect(user['recurring_reminder_minute'], 540, reason: '9:00');

      final rule = (await db.query('recurring_rules')).single;
      expect(rule['next_due_date'], '2026-10-05', reason: 'intact');
    },
  );

  group('the CHECKs', () {
    setUp(() => DatabaseHelper.migrate(db));

    Future<void> refused(String column, Object? value) => expectLater(
      db.update('users', {column: value}),
      throwsA(isA<DatabaseException>()),
      reason: '$column = $value',
    );

    test('enabled is a flag', () async {
      await db.update('users', {'recurring_reminders_enabled': 1});
      await refused('recurring_reminders_enabled', 2);
    });

    test('days before runs from 0 to 7', () async {
      for (final days in [0, 7]) {
        await db.update('users', {'recurring_reminder_days_before': days});
      }
      await refused('recurring_reminder_days_before', -1);
      await refused('recurring_reminder_days_before', 8);
    });

    test('the minute is inside one day', () async {
      for (final minute in [0, 1439]) {
        await db.update('users', {'recurring_reminder_minute': minute});
      }
      await refused('recurring_reminder_minute', -1);
      await refused('recurring_reminder_minute', 1440);
    });

    test('none accepts null', () async {
      await refused('recurring_reminders_enabled', null);
      await refused('recurring_reminder_days_before', null);
      await refused('recurring_reminder_minute', null);
    });
  });

  test('v6 is the latest version', () {
    expect(schemaMigrations[v6SchemaVersion], v6Statements);
    expect(latestSchemaVersion, v6SchemaVersion);
  });
}
