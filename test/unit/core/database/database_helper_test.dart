@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/encryption_key_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Records what it was asked for, so a test can prove the key is fetched once
/// and reused rather than regenerated per open.
class _RecordingKeyStore implements EncryptionKeyStore {
  int calls = 0;
  String? issued;

  @override
  Future<String> getOrCreateKey() async {
    calls++;
    return issued ??= 'test-key-${DateTime.now().microsecondsSinceEpoch}';
  }
}

void main() {
  sqfliteFfiInit();

  late DatabaseHelper helper;
  late _RecordingKeyStore keyStore;

  setUp(() {
    keyStore = _RecordingKeyStore();
    helper = DatabaseHelper(
      dbFactory: databaseFactoryFfi,
      keyStore: keyStore,
      databaseName: inMemoryDatabasePath,
    );
  });

  tearDown(() async => helper.close());

  group('opening', () {
    test('applies the schema on a fresh database', () async {
      final db = await helper.database;

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      );
      final names = tables.map((r) => r['name']! as String).toSet();

      expect(names, contains('transactions'));
      expect(names, contains('schema_migrations'));
    });

    test('enables foreign keys, without which every REFERENCES is inert', () async {
      // SQLite defaults this to OFF, per connection. If onConfigure ever stops
      // running, the schema keeps its constraints on paper and enforces none
      // of them — including the cascades that stop orphaned rows.
      final db = await helper.database;
      final result = await db.rawQuery('PRAGMA foreign_keys');
      expect(result.first.values.first, 1);
    });

    test('records the version it applied', () async {
      final db = await helper.database;
      expect(await DatabaseHelper.appliedVersions(db), {1});
    });

    test('reuses the open connection rather than reopening', () async {
      final first = await helper.database;
      final second = await helper.database;

      expect(identical(first, second), isTrue);
      expect(
        keyStore.calls,
        1,
        reason: 'the key should be fetched once per open, not per access',
      );
    });
  });

  group('migration runner', () {
    test('is idempotent — running it again applies nothing', () async {
      final db = await helper.database;
      final before = await db.query('schema_migrations');

      // The real scenario this guards: every app launch calls onOpen, so
      // migrate() runs on an already-migrated database far more often than on
      // a fresh one. If it were not idempotent, the second launch would fail
      // with "table transactions already exists" and the app would be dead on
      // arrival for every existing user.
      await DatabaseHelper.migrate(db);

      final after = await db.query('schema_migrations');
      expect(after.length, before.length);
    });

    test('leaves no partial schema when a migration fails', () async {
      // A migration that throws halfway must roll back completely. The state
      // to avoid is a schema that is neither the old version nor the new one,
      // because nothing can then decide what to do with it.
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      await db.execute(createSchemaMigrationsForTest);

      await expectLater(
        db.transaction((txn) async {
          await txn.execute('CREATE TABLE good (id INTEGER PRIMARY KEY)');
          await txn.execute('CREATE TABLE bad (this is not valid sql');
        }),
        throwsA(isA<DatabaseException>()),
      );

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'good'",
      );
      expect(
        tables,
        isEmpty,
        reason: 'the successful statement must roll back with the failing one',
      );
    });

    test('latestSchemaVersion matches the highest migration defined', () {
      expect(
        latestSchemaVersion,
        schemaMigrations.keys.reduce((a, b) => a > b ? a : b),
      );
    });
  });

  group('encryption key', () {
    test(
      'generates a 256-bit key and returns the same one thereafter',
      () async {
        final store = InMemoryKeyStore();

        final first = await store.getOrCreateKey();
        final second = await store.getOrCreateKey();

        expect(
          first,
          second,
          reason: 'a changing key orphans the whole database',
        );
        // base64url of 32 bytes is 43 chars unpadded, 44 padded.
        expect(first.length, greaterThanOrEqualTo(43));
      },
    );

    test('two stores do not produce the same key', () async {
      // Guards against a fixed or clock-seeded key, which would make every
      // installation's database openable with the same secret.
      final a = await InMemoryKeyStore().getOrCreateKey();
      final b = await InMemoryKeyStore().getOrCreateKey();
      expect(a, isNot(b));
    });
  });
}

/// The runner's own bookkeeping table, duplicated here so the rollback test
/// does not depend on the migration list it is testing around.
const String createSchemaMigrationsForTest = '''
CREATE TABLE IF NOT EXISTS schema_migrations (
  version     INTEGER PRIMARY KEY,
  applied_at  TEXT NOT NULL
)''';
