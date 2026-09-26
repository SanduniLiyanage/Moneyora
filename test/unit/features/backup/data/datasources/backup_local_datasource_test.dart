@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_change_bus.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/ports/receipt_photo_store.dart';
import 'package:moneyora/features/backup/data/datasources/backup_codec.dart';
import 'package:moneyora/features/backup/data/datasources/backup_local_datasource.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Two phones, as two real in-memory databases carrying every migration,
/// each with its own photo vault. The claims are about the data: that what
/// one phone backs up, another restores whole — rows that name each other,
/// photos sealed again under the new phone's key — and that a restore
/// which cannot finish leaves the new phone exactly as it was.
void main() {
  sqfliteFfiInit();

  // PBKDF2 at its real work factor costs the VM seconds per seal.
  const codec = BackupCodec(iterations: 1000);
  const password = 'correct horse battery';
  final now = DateTime.utc(2026, 9, 27, 10);

  late Database oldPhone;
  late Database newPhone;
  late _FakePhotos oldPhotos;
  late _FakePhotos newPhotos;
  late DatabaseChangeBus bus;
  var notified = 0;

  Future<Database> openPhone() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onOpen: DatabaseHelper.migrate,
      ),
    );
    await applyDefaultSeed(db);
    return db;
  }

  BackupLocalDataSourceImpl sourceOn(Database db, _FakePhotos photos) =>
      BackupLocalDataSourceImpl(
        db,
        photos: photos,
        changeBus: bus,
        codec: codec,
      );

  Future<int> firstId(Database db, String table, [String? where]) async =>
      (await db.query(
            table,
            where: where,
            orderBy: 'id',
            limit: 1,
          )).single['id']!
          as int;

  /// A month of rent that repeats, and a receipt with its photo: the two
  /// shapes a naive restore breaks — rows naming each other, and a path
  /// that means nothing on the next phone.
  Future<void> fillOldPhone() async {
    final account = await firstId(oldPhone, 'accounts');
    final category = await firstId(oldPhone, 'categories', "type = 'expense'");
    const stamp = '2026-09-01T00:00:00Z';
    final rent = await oldPhone.insert('transactions', {
      'account_id': account,
      'category_id': category,
      'amount_cents': 4500000,
      'type': 'expense',
      'date': '2026-09-01',
      'is_recurring': 1,
      'created_at': stamp,
      'updated_at': stamp,
    });
    final rule = await oldPhone.insert('recurring_rules', {
      'template_tx_id': rent,
      'frequency': 'monthly',
      'day_of_month': 1,
      'start_date': '2026-09-01',
      'next_due_date': '2026-10-01',
    });
    await oldPhone.update(
      'transactions',
      {'recurring_rule_id': rule},
      where: 'id = ?',
      whereArgs: [rent],
    );

    const photo = '/old/receipts/aa.jpg.enc';
    oldPhotos.files[photo] = Uint8List.fromList([1, 2, 3]);
    final scan = await oldPhone.insert('receipt_scans', {
      'user_id': 1,
      'image_path': photo,
      'status': 'confirmed',
      'created_at': stamp,
    });
    await oldPhone.insert('transactions', {
      'account_id': account,
      'category_id': category,
      'amount_cents': 279000,
      'type': 'expense',
      'date': '2026-09-16',
      'receipt_scan_id': scan,
      'receipt_image_path': photo,
      'created_at': stamp,
      'updated_at': stamp,
    });
  }

  setUp(() async {
    oldPhone = await openPhone();
    newPhone = await openPhone();
    oldPhotos = _FakePhotos('/old');
    newPhotos = _FakePhotos('/new');
    notified = 0;
    bus = DatabaseChangeBus();
    bus.changes.listen((_) => notified++);
    await fillOldPhone();
  });

  tearDown(() async {
    await oldPhone.close();
    await newPhone.close();
    await bus.close();
  });

  Future<Uint8List> backUp() async =>
      (await sourceOn(oldPhone, oldPhotos).create(password, now: now)).bytes;

  test('names the file by its day and seals it', () async {
    final file = await sourceOn(oldPhone, oldPhotos).create(password, now: now);

    expect(file.name, 'moneyora-2026-09-27.mora');
    final bytes = file.bytes;
    expect(bytes.sublist(0, 4), BackupCodec.magic);
    // Nothing in the file reads as the ledger it holds.
    expect(String.fromCharCodes(bytes).contains('receipt_scans'), isFalse);
  });

  test('another phone restores every row, rows naming each other '
      'included', () async {
    final path = await backUp();

    final summary = await sourceOn(newPhone, newPhotos).restore(path, password);

    for (final table in ['accounts', 'categories', 'recurring_rules']) {
      expect(
        await newPhone.query(table),
        await oldPhone.query(table),
        reason: table,
      );
    }
    final rent = (await newPhone.query('transactions', orderBy: 'id')).first;
    final rule = (await newPhone.query('recurring_rules')).single;
    expect(rule['template_tx_id'], rent['id']);
    expect(rent['recurring_rule_id'], rule['id']);
    expect(summary.transactionCount, 2);
    expect(summary.backedUpAt, now);
  });

  test('seals the photos again under the new phone and points the rows at '
      'them', () async {
    final path = await backUp();

    final summary = await sourceOn(newPhone, newPhotos).restore(path, password);

    final scan = (await newPhone.query('receipt_scans')).single;
    final kept = scan['image_path']! as String;
    expect(kept, startsWith('/new/'));
    expect(kept, endsWith('.jpg.enc'));
    expect(newPhotos.files[kept], [1, 2, 3]);
    final line = (await newPhone.query(
      'transactions',
      where: 'receipt_scan_id IS NOT NULL',
    )).single;
    expect(line['receipt_image_path'], kept);
    expect(summary.photoCount, 1);
  });

  test("discards the photos the new phone's replaced rows kept", () async {
    const stale = '/new/receipts/stale.jpg.enc';
    newPhotos.files[stale] = Uint8List.fromList([9]);
    await newPhone.insert('receipt_scans', {
      'user_id': 1,
      'image_path': stale,
      'created_at': '2026-01-01T00:00:00Z',
    });

    await sourceOn(newPhone, newPhotos).restore(await backUp(), password);

    expect(newPhotos.files.containsKey(stale), isFalse);
  });

  test('tells every screen the data changed', () async {
    final path = await backUp();
    notified = 0;

    await sourceOn(newPhone, newPhotos).restore(path, password);
    await Future<void>.delayed(Duration.zero);

    expect(notified, 1);
  });

  test('a wrong password changes nothing', () async {
    final path = await backUp();
    final before = await newPhone.query('transactions');

    await expectLater(
      sourceOn(newPhone, newPhotos).restore(path, 'not the password'),
      throwsA(
        isA<EncryptionException>().having(
          (e) => e.message,
          'message',
          'That password does not open this backup.',
        ),
      ),
    );
    expect(await newPhone.query('transactions'), before);
    expect(newPhotos.files, isEmpty);
  });

  test('a file that is not a backup is refused', () async {
    final path = Uint8List.fromList('groceries: 1200'.codeUnits);

    await expectLater(
      sourceOn(newPhone, newPhotos).restore(path, password),
      throwsA(
        isA<CacheException>().having(
          (e) => e.message,
          'message',
          'That file is not a Moneyora backup.',
        ),
      ),
    );
  });

  test('a backup from a newer schema is refused', () async {
    final path = await codec.seal({
      'app': 'moneyora',
      'format': 1,
      'schemaVersion': latestSchemaVersion + 1,
      'createdAt': now.toIso8601String(),
      'tables': <String, Object?>{},
      'photos': <String, Object?>{},
    }, password);

    await expectLater(
      sourceOn(newPhone, newPhotos).restore(path, password),
      throwsA(isA<CacheException>()),
    );
    expect(await newPhone.query('accounts'), isNotEmpty);
  });

  test('an older backup missing a later column restores with its '
      'default', () async {
    // What a v4 phone would have written: the users row before v5 added
    // budget alerts.
    final contents = await _contentsOf(backUp, codec, password);
    final users = (contents['tables']! as Map)['users'] as List;
    (users.single as Map).remove('budget_alerts_enabled');
    contents['schemaVersion'] = 4;
    final path = await codec.seal(contents, password);

    await sourceOn(newPhone, newPhotos).restore(path, password);

    expect((await newPhone.query('users')).single['budget_alerts_enabled'], 0);
  });

  test('a restore that fails partway changes nothing and keeps no '
      'photo', () async {
    final contents = await _contentsOf(backUp, codec, password);
    final rows = (contents['tables']! as Map)['transactions'] as List;
    // A row the schema refuses, after rows it accepted.
    (rows.last as Map)['amount_cents'] = -1;
    final path = await codec.seal(contents, password);
    final before = await newPhone.query('accounts');

    await expectLater(
      sourceOn(newPhone, newPhotos).restore(path, password),
      throwsA(
        isA<CacheException>().having(
          (e) => e.message,
          'message',
          'That backup could not be restored. Nothing was changed.',
        ),
      ),
    );
    expect(await newPhone.query('accounts'), before);
    expect(await newPhone.query('transactions'), isEmpty);
    expect(newPhotos.files, isEmpty);
  });

  group('clearAll. FR-SET-009', () {
    test('leaves exactly what a first launch writes', () async {
      final fresh = await openPhone();
      addTearDown(fresh.close);

      await sourceOn(oldPhone, oldPhotos).clearAll();

      expect(await oldPhone.query('transactions'), isEmpty);
      expect(await oldPhone.query('recurring_rules'), isEmpty);
      expect(await oldPhone.query('receipt_scans'), isEmpty);
      for (final table in ['accounts', 'categories']) {
        final names = (await oldPhone.query(table)).map((r) => r['name']);
        final seeded = (await fresh.query(table)).map((r) => r['name']);
        expect(names, seeded, reason: table);
      }
      expect(await oldPhone.query('users'), hasLength(1));
    });

    test('deletes the kept photos and tells every screen', () async {
      notified = 0;

      await sourceOn(oldPhone, oldPhotos).clearAll();
      await Future<void>.delayed(Duration.zero);

      expect(oldPhotos.files, isEmpty);
      expect(notified, 1);
    });
  });

  group('exportCsv. FR-RPT-007', () {
    Future<List<String>> exportLines() async {
      final file = await sourceOn(oldPhone, oldPhotos).exportCsv(now: now);
      expect(file.name, 'moneyora-transactions-2026-09-27.csv');
      // The byte-order mark, as bytes: utf8.decode drops it.
      expect(file.bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      return utf8.decode(file.bytes.sublist(3)).split('\r\n')..removeLast();
    }

    test('one row per transaction, oldest first, amounts signed', () async {
      final lines = await exportLines();

      expect(lines.first, 'Date,Type,Amount,Currency,Account,Category,Note');
      expect(lines, hasLength(3));
      expect(lines[1], startsWith('2026-09-01,Expense,-45000.00,LKR,'));
      expect(lines[2], startsWith('2026-09-16,Expense,-2790.00,LKR,'));
    });

    test('quotes what would break a column, and defuses a formula', () async {
      await oldPhone.update(
        'transactions',
        {'note': 'Rice, "red", 5kg'},
        where: 'date = ?',
        whereArgs: ['2026-09-01'],
      );
      await oldPhone.update(
        'transactions',
        {'note': '=HYPERLINK("x")'},
        where: 'date = ?',
        whereArgs: ['2026-09-16'],
      );

      final lines = await exportLines();

      expect(lines[1], endsWith(',"Rice, ""red"", 5kg"'));
      expect(lines[2], endsWith(',"\'=HYPERLINK(""x"")"'));
    });
  });
}

/// The contents of a fresh backup, opened, for a test to alter.
Future<Map<String, Object?>> _contentsOf(
  Future<Uint8List> Function() backUp,
  BackupCodec codec,
  String password,
) async => codec.open(await backUp(), password);

/// A vault per phone: paths under its own root, bytes in memory.
class _FakePhotos implements ReceiptPhotoStore {
  _FakePhotos(this.root);

  final String root;
  final Map<String, Uint8List> files = {};
  var _next = 0;

  @override
  Future<Uint8List?> read(String path) async => files[path];

  @override
  Future<String> keepBytes(Uint8List bytes, {required String extension}) async {
    final path = '$root/receipts/${_next++}$extension.enc';
    files[path] = bytes;
    return path;
  }

  @override
  Future<void> discard(String path) async => files.remove(path);
}
