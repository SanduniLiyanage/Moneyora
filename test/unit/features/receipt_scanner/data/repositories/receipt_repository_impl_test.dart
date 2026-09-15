import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/ocr_local_datasource.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/receipt_image_local_datasource.dart';
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
  AppException? throwWith;

  @override
  Future<int> insert(ReceiptScanModel scan) async {
    if (throwWith case final e?) throw e;
    inserted = scan;
    return 42;
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

void main() {
  late _FakeOcr ocr;
  late _FakeScans scans;
  late _FakeImages images;
  late ReceiptRepositoryImpl repository;

  setUp(() {
    ocr = _FakeOcr();
    scans = _FakeScans();
    images = _FakeImages();
    repository = ReceiptRepositoryImpl(ocr, scans, images);
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
}
