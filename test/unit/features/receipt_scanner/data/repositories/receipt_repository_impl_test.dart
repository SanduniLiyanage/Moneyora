import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/ocr_local_datasource.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/receipt_image_local_datasource.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/receipt_image_vault.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/receipt_scan_local_datasource.dart';
import 'package:moneyora/features/receipt_scanner/data/models/receipt_scan_model.dart';
import 'package:moneyora/features/receipt_scanner/data/repositories/receipt_repository_impl.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';

class _FakeOcr implements OcrLocalDataSource {
  RecognisedText text = const RecognisedText([]);
  AppException? throwWith;
  String? askedFor;

  @override
  Future<RecognisedText> recognise(String imagePath) async {
    askedFor = imagePath;
    if (throwWith case final e?) throw e;
    return text;
  }
}

class _FakeScans implements ReceiptScanLocalDataSource {
  ReceiptScanModel? inserted;
  List<ReceiptScanModel> stored = const [];
  AppException? throwWith;

  @override
  Future<int> insert(ReceiptScanModel scan) async {
    if (throwWith case final e?) throw e;
    inserted = scan;
    return 42;
  }

  @override
  Future<List<ReceiptScanModel>> listAll() async {
    if (throwWith case final e?) throw e;
    return stored;
  }
}

class _FakeImages implements ReceiptImageLocalDataSource {
  String? path;
  AppException? throwWith;
  ReceiptImageSource? askedFor;

  @override
  Future<String?> pick(ReceiptImageSource source) async {
    askedFor = source;
    if (throwWith case final e?) throw e;
    return path;
  }
}

/// A vault that "holds" every `.enc` path and hands the recogniser a
/// plain copy at a known path, so the test can see which path was read.
class _FakeVault implements ReceiptImageVault {
  AppException? throwWith;
  String? kept;
  String? readPath;
  Uint8List? bytes = Uint8List.fromList([1, 2, 3]);
  final List<String> copies = [];
  bool copyDeleted = false;

  @override
  bool holds(String path) => path.endsWith('.enc');

  @override
  Future<String> keep(String sourcePath) async {
    if (throwWith case final e?) throw e;
    kept = sourcePath;
    return '/documents/receipts/abcd.jpg.enc';
  }

  @override
  Future<Uint8List?> read(String path) async {
    if (throwWith case final e?) throw e;
    readPath = path;
    return bytes;
  }

  @override
  Future<T> withPlainCopy<T>(
    String path,
    Future<T> Function(String plainPath) body,
  ) async {
    if (throwWith case final e?) throw e;
    copies.add(path);
    try {
      return await body('/tmp/plain-copy.jpg');
    } finally {
      copyDeleted = true;
    }
  }

  @override
  Future<String> keepBytes(Uint8List bytes, {required String extension}) =>
      throw UnimplementedError('keepBytes');

  @override
  Future<void> discard(String path) => throw UnimplementedError('discard');
}

void main() {
  late _FakeOcr ocr;
  late _FakeScans scans;
  late _FakeImages images;
  late _FakeVault vault;
  late ReceiptRepositoryImpl repository;

  setUp(() {
    ocr = _FakeOcr();
    scans = _FakeScans();
    images = _FakeImages();
    vault = _FakeVault();
    repository = ReceiptRepositoryImpl(ocr, scans, images, vault);
  });

  group('pickImage', () {
    test('returns the path the picker gave, for the source asked', () async {
      images.path = '/cache/receipt.jpg';

      final result = await repository.pickImage(ReceiptImageSource.gallery);

      expect(result, const Right<Failure, String?>('/cache/receipt.jpg'));
      expect(images.askedFor, ReceiptImageSource.gallery);
    });

    test('a cancelled pick is Right(null), not a failure', () async {
      final result = await repository.pickImage(ReceiptImageSource.camera);

      expect(result, const Right<Failure, String?>(null));
    });

    test(
      'a PermissionException is a PermissionFailure, message kept',
      () async {
        images.throwWith = const PermissionException('camera refused');

        final result = await repository.pickImage(ReceiptImageSource.camera);

        expect(
          result,
          const Left<Failure, String?>(PermissionFailure('camera refused')),
        );
      },
    );
  });

  test('returns what the recogniser read', () async {
    ocr.text = RecognisedText.fromString('KEELLS SUPER\nRICE 5KG 1,250.00');

    final result = await repository.scanReceipt('/cache/receipt.jpg');

    expect(ocr.askedFor, '/cache/receipt.jpg');
    expect(result.getOrElse((f) => fail('$f')).lines, [
      'KEELLS SUPER',
      'RICE 5KG 1,250.00',
    ]);
  });

  test('a kept photo is read through a plain copy, which is gone after '
      '(FR-RCP-012, FR-RCP-014)', () async {
    ocr.text = RecognisedText.fromString('KEELLS SUPER');

    final result = await repository.scanReceipt(
      '/documents/receipts/abcd.jpg.enc',
    );

    expect(vault.copies, ['/documents/receipts/abcd.jpg.enc']);
    expect(ocr.askedFor, '/tmp/plain-copy.jpg');
    expect(vault.copyDeleted, isTrue);
    expect(result.getOrElse((f) => fail('$f')).lines, ['KEELLS SUPER']);
  });

  test('the picker\'s file is handed to the recogniser as it is', () async {
    await repository.scanReceipt('/cache/receipt.jpg');

    expect(vault.copies, isEmpty);
    expect(ocr.askedFor, '/cache/receipt.jpg');
  });

  test('a kept photo that will not open is an EncryptionFailure, '
      'message kept', () async {
    vault.throwWith = const EncryptionException('could not unlock');

    expect(
      await repository.scanReceipt('/documents/receipts/abcd.jpg.enc'),
      const Left<Failure, RecognisedText>(
        EncryptionFailure('could not unlock'),
      ),
    );
  });

  test('an OcrException is an OcrFailure, message kept', () async {
    // The datasource's message tells the photo apart from the parse; losing
    // it would leave FR-RCP-011's badge with nothing to say.
    ocr.throwWith = const OcrException('No text was found on that image.');

    expect(
      await repository.scanReceipt('/cache/blank.jpg'),
      const Left<Failure, RecognisedText>(
        OcrFailure('No text was found on that image.'),
      ),
    );
  });

  test('a PermissionException is a PermissionFailure', () async {
    ocr.throwWith = const PermissionException('Camera access was denied.');

    expect(
      await repository.scanReceipt('/cache/receipt.jpg'),
      const Left<Failure, RecognisedText>(
        PermissionFailure('Camera access was denied.'),
      ),
    );
  });

  group('keepImage', () {
    test('returns where the vault put it', () async {
      final result = await repository.keepImage('/cache/receipt.jpg');

      expect(vault.kept, '/cache/receipt.jpg');
      expect(
        result,
        const Right<Failure, String>('/documents/receipts/abcd.jpg.enc'),
      );
    });

    test('a source that is gone is a CacheFailure, message kept', () async {
      vault.throwWith = const CacheException('The photo is no longer here.');

      expect(
        await repository.keepImage('/cache/gone.jpg'),
        const Left<Failure, String>(
          CacheFailure('The photo is no longer here.'),
        ),
      );
    });

    test('a key that could not be had is an EncryptionFailure', () async {
      vault.throwWith = const EncryptionException('no keychain');

      expect(
        await repository.keepImage('/cache/receipt.jpg'),
        const Left<Failure, String>(EncryptionFailure('no keychain')),
      );
    });
  });

  group('loadImage', () {
    test(
      'returns the vault\'s bytes, or null for a photo that is gone',
      () async {
        expect(
          (await repository.loadImage('/documents/receipts/abcd.jpg.enc'))
              .getOrElse((f) => fail('$f')),
          [1, 2, 3],
        );
        expect(vault.readPath, '/documents/receipts/abcd.jpg.enc');

        vault.bytes = null;
        expect(
          await repository.loadImage('/documents/receipts/gone.jpg.enc'),
          const Right<Failure, Uint8List?>(null),
        );
      },
    );

    test('a photo that will not open is an EncryptionFailure', () async {
      vault.throwWith = const EncryptionException('altered');

      expect(
        await repository.loadImage('/documents/receipts/abcd.jpg.enc'),
        const Left<Failure, Uint8List?>(EncryptionFailure('altered')),
      );
    });
  });

  group('confirmScan', () {
    const scan = ReceiptScan(
      imagePath: '/receipts/keells.jpg',
      status: ReceiptScanStatus.confirmed,
      merchantName: 'KEELLS SUPER',
      confidence: 65,
      items: [
        ReceiptScanItem(
          item: ReceiptLineItem(name: 'RICE 5KG', totalPriceCents: 125000),
          suggestedCategoryId: 7,
          confirmedCategoryId: 7,
          confidence: 90,
        ),
      ],
    );

    test('wraps the entity as a model and returns the id', () async {
      final result = await repository.confirmScan(scan);

      expect(result, const Right<Failure, int>(42));
      final model = scans.inserted!;
      expect(model.imagePath, scan.imagePath);
      expect(model.status, scan.status);
      expect(model.merchantName, scan.merchantName);
      expect(model.confidence, scan.confidence);
      expect(model.userId, 1);
      expect(model.itemModels.single.item.name, 'RICE 5KG');
    });

    test('a CacheException is a CacheFailure', () async {
      scans.throwWith = const CacheException('Could not save the receipt.');

      expect(
        await repository.confirmScan(scan),
        const Left<Failure, int>(CacheFailure('Could not save the receipt.')),
      );
    });
  });

  group('getScanHistory', () {
    test('returns what the datasource read, as entities', () async {
      scans.stored = [
        ReceiptScanModel(
          id: 2,
          scannedAt: DateTime(2026, 9, 14),
          imagePath: '/receipts/keells.jpg',
          status: ReceiptScanStatus.confirmed,
          merchantName: 'KEELLS SUPER',
          totalCents: 190000,
          items: const [
            ReceiptScanItemModel(
              item: ReceiptLineItem(name: 'RICE 5KG', totalPriceCents: 125000),
              confirmedCategoryId: 7,
              confidence: 90,
            ),
          ],
        ),
        ReceiptScanModel(
          id: 1,
          scannedAt: DateTime(2026, 9, 1),
          imagePath: '/receipts/cargills.jpg',
          status: ReceiptScanStatus.confirmed,
          items: const [],
        ),
      ];

      final result = await repository.getScanHistory();

      final history = result.getOrElse((f) => fail('$f'));
      expect(history.map((s) => s.id), [2, 1]);
      expect(history.first.merchantName, 'KEELLS SUPER');
      expect(history.first.scannedAt, DateTime(2026, 9, 14));
      expect(history.first.items.single.item.name, 'RICE 5KG');
      expect(history.first.items.single.confirmedCategoryId, 7);
      expect(history.last.items, isEmpty);
    });

    test('a CacheException is a CacheFailure', () async {
      scans.throwWith = const CacheException('Could not read the receipts.');

      expect(
        await repository.getScanHistory(),
        const Left<Failure, List<ReceiptScan>>(
          CacheFailure('Could not read the receipts.'),
        ),
      );
    });
  });
}
