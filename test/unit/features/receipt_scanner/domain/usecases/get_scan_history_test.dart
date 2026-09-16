import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/get_scan_history.dart';

class _FakeRepository implements ReceiptRepository {
  Either<Failure, List<ReceiptScan>> history = const Right([]);
  int reads = 0;

  @override
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory() async {
    reads++;
    return history;
  }

  @override
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, String>> keepImage(String imagePath) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Uint8List?>> loadImage(String imagePath) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan) =>
      throw UnimplementedError();
}

const _keells = ReceiptScan(
  id: 2,
  imagePath: '/receipts/keells.jpg',
  status: ReceiptScanStatus.confirmed,
  merchantName: 'KEELLS SUPER',
  receiptNumber: '4521',
  totalCents: 190000,
  items: [
    ReceiptScanItem(
      item: ReceiptLineItem(name: 'RICE 5KG', totalPriceCents: 125000),
      confidence: 90,
    ),
    ReceiptScanItem(
      item: ReceiptLineItem(name: 'PANADOL', totalPriceCents: 12000),
      confidence: 20,
    ),
  ],
);

const _cargills = ReceiptScan(
  id: 1,
  imagePath: '/receipts/cargills.jpg',
  status: ReceiptScanStatus.confirmed,
  merchantName: 'Cargills Food City',
  receiptNumber: 'B-77',
  totalCents: 45000,
  items: [
    ReceiptScanItem(
      item: ReceiptLineItem(name: 'Bread', totalPriceCents: 45000),
      confidence: 80,
    ),
  ],
);

/// A scan the parser read nothing off but the lines — no merchant, no
/// number — which the search must still cope with.
const _bare = ReceiptScan(
  id: 3,
  imagePath: '/receipts/bare.jpg',
  status: ReceiptScanStatus.confirmed,
  items: [
    ReceiptScanItem(
      item: ReceiptLineItem(name: 'Milk', totalPriceCents: 100),
      confidence: 50,
    ),
  ],
);

void main() {
  late _FakeRepository repository;
  late GetScanHistory getHistory;

  setUp(() {
    repository = _FakeRepository()
      ..history = const Right([_bare, _keells, _cargills]);
    getHistory = GetScanHistory(repository);
  });

  Future<List<ReceiptScan>> search(String text) async =>
      (await getHistory(ReceiptHistoryQuery(search: text)))
          .getOrElse((f) => fail('$f'));

  test('with no search, returns every scan in the order the repository '
      'gave', () async {
    expect(await search(''), [_bare, _keells, _cargills]);
    expect(repository.reads, 1);
  });

  test('a blank search is no search', () async {
    expect(await search('   '), [_bare, _keells, _cargills]);
  });

  test('matches the merchant, case-insensitively, as a substring', () async {
    expect(await search('keel'), [_keells]);
    expect(await search('FOOD CITY'), [_cargills]);
  });

  test('matches the printed receipt number', () async {
    expect(await search('4521'), [_keells]);
    expect(await search('b-77'), [_cargills]);
  });

  test('matches an item name, on a scan with no merchant too', () async {
    expect(await search('pana'), [_keells]);
    expect(await search('milk'), [_bare]);
  });

  test('every word must match, and they may match different fields', () async {
    expect(await search('keells rice'), [_keells]);
    expect(await search('keells 4521'), [_keells]);
    expect(await search('keells bread'), isEmpty);
  });

  test('nothing matches the total or the date', () async {
    expect(await search('1900'), isEmpty);
    expect(await search('190000'), isEmpty);
  });

  test('no match is an empty list, not a failure', () async {
    expect(await search('zzz'), isEmpty);
  });

  test('a failure reading passes through', () async {
    repository.history = const Left(CacheFailure('disk is full'));

    expect(
      await getHistory(const ReceiptHistoryQuery(search: 'keells')),
      const Left<Failure, List<ReceiptScan>>(CacheFailure('disk is full')),
    );
  });

  test('termsOf splits on any whitespace and lower-cases', () {
    expect(GetScanHistory.termsOf('  Keells\t RICE\n'), ['keells', 'rice']);
    expect(GetScanHistory.termsOf(''), isEmpty);
  });
}
