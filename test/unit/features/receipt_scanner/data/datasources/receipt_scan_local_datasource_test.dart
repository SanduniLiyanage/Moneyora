@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/receipt_scan_local_datasource.dart';
import 'package:moneyora/features/receipt_scanner/data/models/receipt_scan_model.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Against a real in-memory SQLite at the current schema, because the
/// claims here are SQLite's: that the items go with their scan or not at
/// all, that the foreign keys hold, that v3's column takes the number.
void main() {
  sqfliteFfiInit();

  late Database db;
  late ReceiptScanLocalDataSourceImpl scans;
  late int food;
  late int health;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          final batch = d.batch();
          for (final version in schemaMigrations.keys.toList()..sort()) {
            for (final statement in schemaMigrations[version]!) {
              batch.execute(statement);
            }
          }
          await batch.commit(noResult: true);
        },
        version: latestSchemaVersion,
      ),
    );
    await applyDefaultSeed(db);

    Future<int> idOf(String name) async =>
        (await db.query(
              'categories',
              columns: ['id'],
              where: 'name = ?',
              whereArgs: [name],
            )).single['id']!
            as int;
    food = await idOf('Food');
    health = await idOf('Health');

    scans = ReceiptScanLocalDataSourceImpl(db);
  });

  tearDown(() => db.close());

  ReceiptScanModel scan({
    List<ReceiptScanItemModel>? items,
    ReceiptScanStatus status = ReceiptScanStatus.confirmed,
    DateTime? scannedAt,
    String merchantName = 'KEELLS SUPER',
  }) => ReceiptScanModel(
    imagePath: '/receipts/keells.jpg',
    status: status,
    scannedAt: scannedAt,
    merchantName: merchantName,
    receiptDate: DateTime(2026, 4, 3, 14, 32),
    totalCents: 190000,
    taxCents: 0,
    receiptNumber: '4521',
    confidence: 65,
    items:
        items ??
        [
          ReceiptScanItemModel(
            item: const ReceiptLineItem(
              name: 'RICE 5KG',
              totalPriceCents: 125000,
            ),
            suggestedCategoryId: food,
            confirmedCategoryId: food,
            confidence: 90,
          ),
          ReceiptScanItemModel(
            item: const ReceiptLineItem(
              name: 'PANADOL',
              quantity: 2,
              unitPriceCents: 6000,
              totalPriceCents: 12000,
            ),
            suggestedCategoryId: null,
            confirmedCategoryId: health,
            confidence: 20,
          ),
        ],
  );

  Future<int> countOf(String table) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).single['n']!
          as int;

  test('writes the scan row with every column, v3 number included', () async {
    final id = await scans.insert(scan());

    final row = (await db.query(
      'receipt_scans',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    expect(row['user_id'], 1);
    expect(row['image_path'], '/receipts/keells.jpg');
    expect(row['merchant_name'], 'KEELLS SUPER');
    expect(row['receipt_date'], DateTime(2026, 4, 3, 14, 32).toIso8601String());
    expect(row['total_amount_cents'], 190000);
    expect(row['tax_amount_cents'], 0);
    expect(row['receipt_number'], '4521');
    expect(row['confidence_score'], 65);
    expect(row['status'], 'confirmed');
    expect(row['created_at'], isA<String>());
  });

  test('writes every item under the scan, in order', () async {
    final id = await scans.insert(scan());

    final rows = await db.query(
      'receipt_items',
      where: 'receipt_scan_id = ?',
      whereArgs: [id],
      orderBy: 'id ASC',
    );
    expect(rows.map((r) => r['name']), ['RICE 5KG', 'PANADOL']);
    final panadol = rows.last;
    expect(panadol['quantity'], 2.0);
    expect(panadol['unit_price_cents'], 6000);
    expect(panadol['total_price_cents'], 12000);
    expect(panadol['suggested_category_id'], isNull);
    expect(panadol['confirmed_category_id'], health);
    expect(panadol['confidence_score'], 20);
  });

  test('reads back through the model as it was written', () async {
    final written = scan();
    final id = await scans.insert(written);

    final read = ReceiptScanModel.fromMap(
      (await db.query(
        'receipt_scans',
        where: 'id = ?',
        whereArgs: [id],
      )).single,
      await db.query(
        'receipt_items',
        where: 'receipt_scan_id = ?',
        whereArgs: [id],
        orderBy: 'id ASC',
      ),
    );

    expect(read.id, id);
    expect(read.status, written.status);
    expect(read.merchantName, written.merchantName);
    expect(read.receiptDate, written.receiptDate);
    expect(read.totalCents, written.totalCents);
    expect(read.receiptNumber, written.receiptNumber);
    expect(read.confidence, written.confidence);
    expect(read.items.map((i) => i.item), written.items.map((i) => i.item));
    expect(
      read.items.map((i) => i.confirmedCategoryId),
      written.items.map((i) => i.confirmedCategoryId),
    );
  });

  test('all or none: a bad item rolls the scan back too', () async {
    await expectLater(
      scans.insert(
        scan(
          items: [
            const ReceiptScanItemModel(
              item: ReceiptLineItem(name: 'RICE 5KG', totalPriceCents: 125000),
              confidence: 90,
            ),
            const ReceiptScanItemModel(
              item: ReceiptLineItem(name: 'GHOST', totalPriceCents: 100),
              confirmedCategoryId: 999, // no such category
              confidence: 0,
            ),
          ],
        ),
      ),
      throwsA(isA<CacheException>()),
    );

    expect(await countOf('receipt_scans'), 0);
    expect(await countOf('receipt_items'), 0);
  });

  test('every status the constraint allows round-trips', () async {
    for (final status in ReceiptScanStatus.values) {
      expect(
        ReceiptScanModel.decodeStatus(ReceiptScanModel.encodeStatus(status)),
        status,
      );
      await scans.insert(scan(status: status));
    }
    expect(await countOf('receipt_scans'), 3);
    expect(() => ReceiptScanModel.decodeStatus('lost'), throwsArgumentError);
  });

  test('a scan with no items is still a record', () async {
    // FR-RCP-010's single-category mode may store the total with no
    // lines; the row is the batch record either way.
    final id = await scans.insert(scan(items: const []));

    expect(id, greaterThan(0));
    expect(await countOf('receipt_items'), 0);
  });

  test('a closed database is a CacheException', () async {
    await db.close();

    expect(() => scans.insert(scan()), throwsA(isA<CacheException>()));
    expect(() => scans.listAll(), throwsA(isA<CacheException>()));
  });

  group('listAll', () {
    test('is empty before anything was scanned', () async {
      expect(await scans.listAll(), isEmpty);
    });

    test('returns every scan newest first, each with its items in printed '
        'order', () async {
      final older = await scans.insert(
        scan(
          merchantName: 'Cargills',
          scannedAt: DateTime(2026, 9, 1, 10),
          items: const [
            ReceiptScanItemModel(
              item: ReceiptLineItem(name: 'Bread', totalPriceCents: 45000),
              confidence: 80,
            ),
          ],
        ),
      );
      final newer = await scans.insert(
        scan(merchantName: 'Keells', scannedAt: DateTime(2026, 9, 14, 18)),
      );
      final bare = await scans.insert(
        scan(
          merchantName: 'Arpico',
          scannedAt: DateTime(2026, 9, 7),
          items: const [],
        ),
      );

      final all = await scans.listAll();

      expect(all.map((s) => s.id), [newer, bare, older]);
      expect(all.map((s) => s.merchantName), ['Keells', 'Arpico', 'Cargills']);
      expect(all.first.items.map((i) => i.item.name), ['RICE 5KG', 'PANADOL']);
      expect(all[1].items, isEmpty);
      expect(all.last.items.single.item.name, 'Bread');
      expect(all.last.items.single.confirmedCategoryId, isNull);
    });

    test('two scans in the same second come back in the order they were '
        'saved', () async {
      final at = DateTime(2026, 9, 14, 18, 30);
      final first = await scans.insert(scan(scannedAt: at));
      final second = await scans.insert(scan(scannedAt: at));

      expect((await scans.listAll()).map((s) => s.id), [second, first]);
    });

    test('scannedAt is when the row was written', () async {
      final before = DateTime.now();
      await scans.insert(scan());

      final read = (await scans.listAll()).single;

      expect(read.scannedAt, isNotNull);
      expect(read.scannedAt!.isBefore(before), isFalse);
      expect(read.scannedAt!.isAfter(DateTime.now()), isFalse);
    });

    test('every column reads back as it was written', () async {
      final written = scan(scannedAt: DateTime(2026, 9, 14, 18, 30, 5));
      final id = await scans.insert(written);

      final read = (await scans.listAll()).single;

      expect(read.id, id);
      expect(read.scannedAt, written.scannedAt);
      expect(read.imagePath, written.imagePath);
      expect(read.status, written.status);
      expect(read.merchantName, written.merchantName);
      expect(read.receiptDate, written.receiptDate);
      expect(read.totalCents, written.totalCents);
      expect(read.taxCents, written.taxCents);
      expect(read.receiptNumber, written.receiptNumber);
      expect(read.confidence, written.confidence);
      expect(read.userId, 1);
      final panadol = read.items.last;
      expect(panadol.item, written.items.last.item);
      expect(panadol.suggestedCategoryId, isNull);
      expect(panadol.confirmedCategoryId, health);
      expect(panadol.confidence, 20);
    });
  });
}
