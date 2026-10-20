@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/encryption_key_store.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Records what it was asked for, so a test can prove the key is fetched once
/// and reused rather than regenerated per open.
class _RecordingKeyStore implements EncryptionKeyStore {
  int calls = 0;
  String? issued;

  /// What the last call said about data already on the phone.
  bool? mustExist;

  @override
  Future<String> getOrCreateKey({bool mustExist = false}) async {
    calls++;
    this.mustExist = mustExist;
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
      expect(await DatabaseHelper.appliedVersions(db), {
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
      });
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

  group('after an update, with a database already on the phone', () {
    late Directory dir;
    late String path;

    late String databases;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('moneyora-helper-');
      // Where the helper looks, as the platform's databases folder is on a
      // phone.
      databases = await databaseFactoryFfi.getDatabasesPath();
      await databaseFactoryFfi.setDatabasesPath(dir.path);
      path = '${dir.path}/moneyora.db';
    });

    tearDown(() async {
      await databaseFactoryFfi.setDatabasesPath(databases);
      await dir.delete(recursive: true);
    });

    DatabaseHelper over(EncryptionKeyStore store) {
      final opened = DatabaseHelper(
        dbFactory: databaseFactoryFfi,
        keyStore: store,
      );
      addTearDown(opened.close);
      return opened;
    }

    test('a first install may make its key', () async {
      final store = _RecordingKeyStore();

      await over(store).database;

      expect(store.mustExist, isFalse);
    });

    test('a database already there asks for the key it was made with, '
        'never a new one. NFR-REL-002', () async {
      await over(InMemoryKeyStore()).database;
      final store = _RecordingKeyStore();

      await over(store).database;

      expect(store.mustExist, isTrue);
    });

    test('without that key it is not opened, and the file is left as it '
        'was', () async {
      final first = over(InMemoryKeyStore());
      await first.database;
      await first.close();
      final before = await File(path).readAsBytes();

      await expectLater(
        over(InMemoryKeyStore()).database,
        throwsA(isA<EncryptionException>()),
      );

      expect(await File(path).readAsBytes(), before);
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
