import 'package:sqflite_sqlcipher/sqflite.dart';

import 'encryption_key_store.dart';
import 'migrations/v1_initial.dart';

/// Every schema version, keyed by the version it produces.
///
/// Migrations are **additive only** — no `DROP COLUMN`, no `DROP TABLE`, no
/// `RENAME` (SDD §5.3). SQLite's `ALTER TABLE` is limited enough that dropping
/// a column means recreating the table and copying every row, and a failure
/// halfway through that on a user's device loses their financial history.
/// Adding a nullable column and leaving the old one unused is almost always
/// the better trade.
///
/// To add a version: write `migrations/vN_*.dart`, add its statement list
/// here, and add a test proving an existing v(N-1) database upgrades to it
/// **with its rows intact**. That last part is the one people skip.
const Map<int, List<String>> schemaMigrations = <int, List<String>>{
  v1SchemaVersion: v1Statements,
};

/// The version a fresh install lands on.
int get latestSchemaVersion =>
    schemaMigrations.keys.reduce((a, b) => a > b ? a : b);

/// Opens the encrypted database and brings its schema up to date.
///
/// Both collaborators are injected rather than constructed internally, because
/// the production ones — SQLCipher and the platform keychain — need a device.
/// Injecting them is what lets the migration runner, the part that can destroy
/// data, be tested on a laptop.
///
/// Implements SDD §5.1 and §5.3, NFR-SEC-001, NFR-MNT-005, NFR-REL-005.
class DatabaseHelper {
  /// Creates a helper over [factory] and [keyStore].
  DatabaseHelper({
    required this.dbFactory,
    required this.keyStore,
    this.databaseName = 'moneyora.db',
  });

  /// Opens connections. `databaseFactoryFfi` in tests, the SQLCipher factory
  /// in production. Named `dbFactory` rather than `factory` because the latter
  /// is a Dart keyword and shadows sqflite's own top-level `databaseFactory`.
  final DatabaseFactory dbFactory;

  /// Supplies the AES-256 key. See [EncryptionKeyStore].
  final EncryptionKeyStore keyStore;

  /// File name inside the platform's database directory.
  final String databaseName;

  Database? _database;

  /// The open database, opening and migrating it on first access.
  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final path = await _resolvePath();
    final password = await keyStore.getOrCreateKey();

    return dbFactory.openDatabase(
      path,
      // SqlCipherOpenDatabaseOptions extends OpenDatabaseOptions, so the
      // plain FFI factory used in tests accepts it and simply ignores
      // `password`. One code path, encrypted in production, openable on a
      // laptop under test.
      options: SqlCipherOpenDatabaseOptions(
        // Deliberately not using sqflite's own `version` / `onCreate` /
        // `onUpgrade`. That machinery tracks a single integer, which cannot
        // answer "which migrations have actually run?" after a restore from
        // backup or a partial upgrade. The schema_migrations table can.
        onConfigure: _configure,
        onOpen: migrate,
        password: password,
      ),
    );
  }

  Future<String> _resolvePath() async {
    if (databaseName == inMemoryDatabasePath) return databaseName;
    final base = await dbFactory.getDatabasesPath();
    return '$base/$databaseName';
  }

  /// Runs before any query, on every open.
  static Future<void> _configure(Database db) async {
    // SQLite ships with foreign keys **off** for backwards compatibility, per
    // connection. Every declared REFERENCES in the schema is inert until this
    // runs — including the ON DELETE CASCADE that stops plan allocations and
    // receipt items outliving their parents.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Applies every migration the database has not yet recorded.
  ///
  /// Visible for testing. Safe to call repeatedly: it is driven by what
  /// `schema_migrations` records, not by a version number handed in.
  static Future<void> migrate(Database db) async {
    await db.execute(createSchemaMigrations);

    final applied = await appliedVersions(db);
    final pending =
        schemaMigrations.keys.where((v) => !applied.contains(v)).toList()
          ..sort();

    for (final version in pending) {
      // One transaction per version. A migration that fails halfway must not
      // leave the schema in a state that is neither the old nor the new one —
      // that is the state from which there is no automated recovery.
      await db.transaction((txn) async {
        for (final statement in schemaMigrations[version]!) {
          await txn.execute(statement);
        }
        await txn.insert('schema_migrations', {
          'version': version,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        });
      });
    }
  }

  /// Versions already applied, ascending.
  static Future<Set<int>> appliedVersions(Database db) async {
    final rows = await db.query('schema_migrations', columns: ['version']);
    return rows.map((r) => r['version']! as int).toSet();
  }

  /// Closes the database. Call on app shutdown and between tests.
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
