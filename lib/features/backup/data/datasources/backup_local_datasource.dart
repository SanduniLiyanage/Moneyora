/// Every row and every kept receipt photo, out to a `.mora` file and back.
/// FR-BAK-001, FR-BAK-005, E-38.
///
/// Throws [AppException] on failure, per the layer contract in
/// `docs/ARCHITECTURE.md` §3; `BackupRepositoryImpl` converts.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/database/database_change_bus.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/database/seed/default_seed.dart';
import '../../../../core/database/seed/keyword_seed.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/ports/receipt_photo_store.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/backup_file.dart';
import '../../domain/entities/restore_summary.dart';
import 'backup_codec.dart';

/// Makes and restores backups. The only holder of SQL for the feature.
abstract class BackupLocalDataSource {
  /// Seals every row and kept photo under [password]. [now] names the file
  /// and is recorded inside it.
  Future<BackupFile> create(String password, {required DateTime now});

  /// Replaces every row with the backup [bytes], opened with [password].
  Future<RestoreSummary> restore(Uint8List bytes, String password);

  /// Deletes every row and every kept photo, and writes the first-launch
  /// defaults back — the state a fresh install opens on. FR-SET-009.
  Future<void> clearAll();

  /// Every transaction as a CSV file, oldest first. [now] names the file.
  /// FR-RPT-007.
  Future<BackupFile> exportCsv({required DateTime now});
}

/// Fulfils [BackupLocalDataSource] over the open database.
///
/// ## What is inside
///
/// The data, not the database file (E-38). The file is SQLCipher-sealed
/// under this phone's keychain key and cannot be opened anywhere else, so
/// the backup carries every table's rows as JSON — `{app, format,
/// schemaVersion, createdAt, tables: {name: [row, …]}, photos: {path:
/// base64}}` — which a restore writes into whatever database the new phone
/// has, under its own key. Tables are read from `sqlite_master`, not a list
/// kept here, so a table a later migration adds is backed up without this
/// file knowing it exists.
///
/// Receipt photos are carried decrypted, inside the sealed file, because
/// the vault's key is derived from the database key and is as local as it
/// is. A restore seals them again under the new phone's key and rewrites
/// the paths the rows keep.
///
/// ## Restoring an older backup
///
/// Migrations are additive (SDD §5.3), so a row from an older schema fits
/// today's table: it has fewer columns, and each missing one has a default.
/// Only the columns today's table has are written. A backup from a newer
/// schema is refused — its rows may carry meaning this version would drop.
class BackupLocalDataSourceImpl implements BackupLocalDataSource {
  /// Creates the datasource.
  BackupLocalDataSourceImpl(
    this._db, {
    required this._photos,
    this._changeBus,
    this._codec = const BackupCodec(),
  });

  final Database _db;
  final ReceiptPhotoStore _photos;
  final DatabaseChangeBus? _changeBus;
  final BackupCodec _codec;

  /// What the `app` field says, so a stray JSON file is not taken for one.
  static const String appName = 'moneyora';

  /// The contents' own layout, separate from the file's.
  static const int contentsFormat = 1;

  /// Tables that are bookkeeping, not data: the migration ledger belongs to
  /// the database a restore writes into, not to the one backed up.
  static const Set<String> _skipped = {'schema_migrations', 'android_metadata'};

  /// Every column that names a kept receipt photo, by table.
  static const Map<String, String> _photoColumns = {
    'transactions': 'receipt_image_path',
    'receipt_scans': 'image_path',
  };

  @override
  Future<BackupFile> create(String password, {required DateTime now}) async {
    final Map<String, Object?> contents;
    try {
      contents = await _dump(now);
    } on DatabaseException catch (e) {
      throw CacheException('Could not read your data to back it up.', cause: e);
    }

    final day = now.toIso8601String().substring(0, 10);
    return BackupFile(
      name: 'moneyora-$day.mora',
      bytes: await _codec.seal(contents, password),
    );
  }

  Future<Map<String, Object?>> _dump(DateTime now) async {
    final tables = <String, Object?>{};
    final photoPaths = <String>{};
    for (final table in await _tableNames(_db)) {
      final rows = await _db.query(table);
      tables[table] = [for (final row in rows) _encodeRow(row)];
      if (_photoColumns[table] case final column?) {
        for (final row in rows) {
          if (row[column] case final String path when path.isNotEmpty) {
            photoPaths.add(path);
          }
        }
      }
    }

    // A photo the phone has since lost is left out, not a failure: its row
    // already shows the "no longer on this phone" placeholder, and will on
    // the next phone too.
    final photos = <String, String>{};
    for (final path in photoPaths) {
      final bytes = await _photos.read(path);
      if (bytes != null) photos[path] = base64Encode(bytes);
    }

    final versions = await DatabaseHelper.appliedVersions(_db);
    return {
      'app': appName,
      'format': contentsFormat,
      'schemaVersion': versions.isEmpty ? 0 : versions.reduce(_max),
      'createdAt': now.toUtc().toIso8601String(),
      'tables': tables,
      'photos': photos,
    };
  }

  @override
  Future<RestoreSummary> restore(Uint8List bytes, String password) async {
    final contents = await _codec.open(bytes, password);

    final tables = _validate(contents);
    final backedUpAt = DateTime.parse(contents['createdAt']! as String);

    // The photos this phone holds now, to be removed once the rows naming
    // them are gone — and only then, so a failed restore loses nothing.
    final replaced = await _keptPhotoPaths();

    // Photos first: sealing is file I/O and cannot share the database
    // transaction, so it happens before it, and is undone if it fails.
    final moved = <String, String>{};
    try {
      final photos = (contents['photos'] as Map<String, Object?>?) ?? {};
      for (final MapEntry(key: oldPath, :value) in photos.entries) {
        moved[oldPath] = await _photos.keepBytes(
          base64Decode(value! as String),
          extension: p.extension(p.withoutExtension(oldPath)),
        );
      }
    } on Object {
      await _discardAll(moved.values);
      rethrow;
    }

    try {
      await _db.transaction((txn) async {
        // transactions and recurring_rules name each other (E-36's
        // template), so no insert order satisfies both. Checks wait for the
        // commit, where the whole restored set is judged at once.
        await txn.execute('PRAGMA defer_foreign_keys = ON');
        final present = await _tableNames(txn);
        for (final table in present) {
          await txn.delete(table);
        }
        for (final table in present) {
          final rows = tables[table];
          if (rows == null) continue;
          final columns = await _columnNames(txn, table);
          final photoColumn = _photoColumns[table];
          for (final raw in rows) {
            final row = <String, Object?>{
              for (final MapEntry(:key, :value)
                  in (raw! as Map<String, Object?>).entries)
                if (columns.contains(key)) key: _decodeValue(value),
            };
            if (photoColumn != null && row[photoColumn] is String) {
              row[photoColumn] = moved[row[photoColumn]] ?? row[photoColumn];
            }
            await txn.insert(table, row);
          }
        }
      });
    } on DatabaseException catch (e) {
      await _discardAll(moved.values);
      throw CacheException(
        'That backup could not be restored. Nothing was changed.',
        cause: e,
      );
    }

    await _discardAll(replaced.difference(moved.values.toSet()));
    _changeBus?.notify();

    final count = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM transactions'),
    );
    return RestoreSummary(
      backedUpAt: backedUpAt,
      transactionCount: count ?? 0,
      photoCount: moved.length,
    );
  }

  @override
  Future<void> clearAll() async {
    final kept = await _keptPhotoPaths();
    try {
      await _db.transaction((txn) async {
        await txn.execute('PRAGMA defer_foreign_keys = ON');
        for (final table in await _tableNames(txn)) {
          await txn.delete(table);
        }
        // What a fresh install opens on: the default account and categories
        // FR-EXP-003 expects, and the dictionary the scanner reads.
        await applyDefaultSeed(txn);
        await applyKeywordSeed(txn);
      });
    } on DatabaseException catch (e) {
      throw CacheException(
        'Your data could not be cleared. Nothing was changed.',
        cause: e,
      );
    }
    await _discardAll(kept);
    _changeBus?.notify();
  }

  @override
  Future<BackupFile> exportCsv({required DateTime now}) async {
    final List<Map<String, Object?>> rows;
    try {
      rows = await _db.rawQuery('''
        SELECT t.date, t.type, t.transfer_direction, t.amount_cents,
               a.currency, a.name AS account, c.name AS category, t.note
        FROM transactions t
        JOIN accounts a ON a.id = t.account_id
        LEFT JOIN categories c ON c.id = t.category_id
        ORDER BY t.date, t.id
      ''');
    } on DatabaseException catch (e) {
      throw CacheException('Could not read your transactions.', cause: e);
    }

    final csv = StringBuffer()
      ..write('Date,Type,Amount,Currency,Account,Category,Note\r\n');
    for (final row in rows) {
      final type = row['type']! as String;
      final out =
          type == 'expense' ||
          (type == 'transfer' && row['transfer_direction'] == 'out');
      final currency = row['currency']! as String;
      final cents = row['amount_cents']! as int;
      csv.write(
        [
          row['date']! as String,
          switch (type) {
            'expense' => 'Expense',
            'income' => 'Income',
            _ => out ? 'Transfer out' : 'Transfer in',
          },
          // Signed, so a spreadsheet's SUM of the column is the net.
          formatCentsPlain(
            out ? -cents : cents,
            currency: CurrencyFormat.forCode(currency),
          ),
          _csvText(currency),
          _csvText(row['account']! as String),
          _csvText((row['category'] as String?) ?? ''),
          _csvText((row['note'] as String?) ?? ''),
        ].join(','),
      );
      csv.write('\r\n');
    }

    final day = now.toIso8601String().substring(0, 10);
    return BackupFile(
      name: 'moneyora-transactions-$day.csv',
      // A byte-order mark, so a spreadsheet opens Sinhala and Tamil notes as
      // text rather than as mojibake.
      bytes: Uint8List.fromList(utf8.encode('﻿$csv')),
    );
  }

  /// [value] as one CSV field: quoted when it holds a comma, a quote or a
  /// line break (RFC 4180), and led by an apostrophe when it would start a
  /// formula — a note reading `=HYPERLINK(...)` is text the user typed, not
  /// something a spreadsheet should run.
  static String _csvText(String value) {
    final safe = value.startsWith(RegExp(r'[=+\-@\t\r]')) ? "'$value" : value;
    if (safe.contains(RegExp('[",\r\n]'))) {
      return '"${safe.replaceAll('"', '""')}"';
    }
    return safe;
  }

  /// Every kept photo the rows name now.
  Future<Set<String>> _keptPhotoPaths() async {
    final paths = <String>{};
    for (final entry in _photoColumns.entries) {
      final rows = await _db.query(entry.key, columns: [entry.value]);
      for (final row in rows) {
        if (row[entry.value] case final String path) paths.add(path);
      }
    }
    return paths;
  }

  /// The tables in [contents], once it is known to be a backup this version
  /// can restore.
  Map<String, List<Object?>> _validate(Map<String, Object?> contents) {
    if (contents['app'] != appName ||
        contents['tables'] is! Map<String, Object?> ||
        contents['createdAt'] is! String ||
        contents['schemaVersion'] is! int) {
      throw const CacheException('That file is not a Moneyora backup.');
    }
    if ((contents['format']! as int) > contentsFormat ||
        (contents['schemaVersion']! as int) > latestSchemaVersion) {
      throw const CacheException(
        'This backup was made by a newer version of Moneyora. Update the '
        'app, then restore it.',
      );
    }
    return {
      for (final MapEntry(:key, :value)
          in (contents['tables']! as Map<String, Object?>).entries)
        key: value! as List<Object?>,
    };
  }

  Future<void> _discardAll(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        await _photos.discard(path);
      } on AppException {
        // A file that would not delete is litter, not data loss; the
        // restore's own outcome is what the user needs to hear.
      }
    }
  }

  static Future<List<String>> _tableNames(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return [
      for (final row in rows)
        if (!_skipped.contains(row['name'])) row['name']! as String,
    ];
  }

  static Future<Set<String>> _columnNames(
    DatabaseExecutor db,
    String table,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info("$table")');
    return {for (final row in rows) row['name']! as String};
  }

  /// A row as JSON can carry it. SQLite hands back integers, reals, text,
  /// null and blobs; only the last needs wrapping.
  static Map<String, Object?> _encodeRow(Map<String, Object?> row) => {
    for (final MapEntry(:key, :value) in row.entries)
      key: value is Uint8List ? {'blob': base64Encode(value)} : value,
  };

  static Object? _decodeValue(Object? value) => switch (value) {
    {'blob': final String data} => base64Decode(data),
    _ => value,
  };

  static int _max(int a, int b) => a > b ? a : b;
}
