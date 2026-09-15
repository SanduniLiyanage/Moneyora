import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/scan_receipt.dart';

class _FakeRepository implements ReceiptRepository {
  Either<Failure, RecognisedText> result = const Right(RecognisedText([]));
  String? askedFor;

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) async {
    askedFor = imagePath;
    return result;
  }
}

void main() {
  late _FakeRepository repository;
  late ScanReceipt scan;

  setUp(() {
    repository = _FakeRepository();
    scan = ScanReceipt(repository);
  });

  test('hands the path to the repository and returns what it read', () async {
    repository.result = Right(RecognisedText.fromString('KEELLS SUPER\nRICE'));

    final result = await scan('/cache/receipt.jpg');

    expect(repository.askedFor, '/cache/receipt.jpg');
    expect(result.getOrElse((f) => fail('$f')).lines, ['KEELLS SUPER', 'RICE']);
  });

  test('a blank path is refused before the recogniser is asked', () async {
    // A cancelled picker, not an unreadable receipt: the message has to say
    // "choose an image", not "try a clearer photo".
    for (final path in ['', '   ']) {
      final result = await scan(path);

      expect(
        result,
        const Left<Failure, RecognisedText>(
          ValidationFailure('No image was chosen.', field: 'imagePath'),
        ),
      );
    }
    expect(repository.askedFor, isNull);
  });

  test('the repository failure passes through untouched', () async {
    repository.result = const Left(OcrFailure());

    expect(
      await scan('/cache/blank.jpg'),
      const Left<Failure, RecognisedText>(OcrFailure()),
    );
  });
}
