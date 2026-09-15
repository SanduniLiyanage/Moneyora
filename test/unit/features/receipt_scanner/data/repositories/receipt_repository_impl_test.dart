import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/ocr_local_datasource.dart';
import 'package:moneyora/features/receipt_scanner/data/repositories/receipt_repository_impl.dart';
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

void main() {
  late _FakeOcr ocr;
  late ReceiptRepositoryImpl repository;

  setUp(() {
    ocr = _FakeOcr();
    repository = ReceiptRepositoryImpl(ocr);
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
}
