import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/load_receipt_image.dart';

class _FakeRepository implements ReceiptRepository {
  Either<Failure, Uint8List?> result = Right(Uint8List.fromList([1, 2, 3]));
  String? askedFor;

  @override
  Future<Either<Failure, Uint8List?>> loadImage(String imagePath) async {
    askedFor = imagePath;
    return result;
  }

  @override
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, String>> keepImage(String imagePath) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory() =>
      throw UnimplementedError();
}

void main() {
  late _FakeRepository repository;
  late LoadReceiptImage load;

  setUp(() {
    repository = _FakeRepository();
    load = LoadReceiptImage(repository);
  });

  test('hands the path to the repository and returns its bytes', () async {
    final result = await load('/receipts/keells.jpg.enc');

    expect(repository.askedFor, '/receipts/keells.jpg.enc');
    expect(result.getOrElse((_) => null), [1, 2, 3]);
  });

  test('a photo that is gone is null, not a failure', () async {
    repository.result = const Right(null);

    final result = await load('/receipts/gone.jpg.enc');

    expect(result, const Right<Failure, Uint8List?>(null));
  });

  test('a blank path is refused before the disk is asked', () async {
    final result = await load('   ');

    expect(repository.askedFor, isNull);
    expect(
      result,
      const Left<Failure, Uint8List?>(
        ValidationFailure('The receipt has no photo.', field: 'imagePath'),
      ),
    );
  });

  test('a failure decrypting passes through as it is', () async {
    repository.result = const Left(EncryptionFailure('altered'));

    final result = await load('/receipts/keells.jpg.enc');

    expect(
      result,
      const Left<Failure, Uint8List?>(EncryptionFailure('altered')),
    );
  });
}
