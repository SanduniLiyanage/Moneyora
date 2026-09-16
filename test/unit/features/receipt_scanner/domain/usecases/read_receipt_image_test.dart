import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/keyword_match.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/keyword_dictionary_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/categorise_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parse_receipt_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/read_receipt_image.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/scan_receipt.dart';

/// The recogniser, scripted: what it "reads" off a path.
class _FakeReceipts implements ReceiptRepository {
  Either<Failure, RecognisedText> answer = const Right(RecognisedText([]));
  String? askedFor;

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) async {
    askedFor = imagePath;
    return answer;
  }

  @override
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory() =>
      throw UnimplementedError();
}

/// One keyword — rice is Food — so a suggestion can be seen to arrive.
class _FakeDictionary implements KeywordDictionaryRepository {
  Failure? failWith;
  final lookups = <String>[];

  @override
  Future<Either<Failure, List<KeywordMatch>>> matchesFor(String text) async {
    lookups.add(text);
    if (failWith case final failure?) return Left(failure);
    return Right(
      text.toLowerCase().contains('rice')
          ? const [
              KeywordMatch(
                keyword: 'rice',
                categoryId: 7,
                categoryName: 'Food',
                matchType: KeywordMatchType.contains,
              ),
            ]
          : const [],
    );
  }

  @override
  Future<Either<Failure, Unit>> learn({
    required String text,
    required int categoryId,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> recordApplied({
    required String text,
    required int categoryId,
  }) => throw UnimplementedError();
}

void main() {
  late _FakeReceipts receipts;
  late _FakeDictionary dictionary;
  late ReadReceiptImage read;

  setUp(() {
    receipts = _FakeReceipts();
    dictionary = _FakeDictionary();
    read = ReadReceiptImage(
      ScanReceipt(receipts),
      const ParseReceiptText(),
      CategoriseReceipt(dictionary),
    );
  });

  test('runs scan, parse and categorise, and keeps the path beside the '
      'result', () async {
    receipts.answer = Right(
      RecognisedText.fromString(
        'KEELLS SUPER\nRICE 5KG 1,250.00\nBREAD 300.00\nTOTAL 1,550.00',
      ),
    );

    final result = await read('/cache/receipt.jpg');

    final scanned = result.getRight().toNullable()!;
    expect(receipts.askedFor, '/cache/receipt.jpg');
    expect(scanned.imagePath, '/cache/receipt.jpg');
    expect(scanned.receipt.receipt.merchantName, 'KEELLS SUPER');
    expect(scanned.receipt.receipt.totalCents, 155000);
    expect(scanned.receipt.items.length, 2);
    expect(scanned.receipt.items[0].suggestion.categoryId, 7);
    expect(scanned.receipt.items[1].suggestion.categoryId, isNull);
    expect(dictionary.lookups, contains('RICE 5KG'));
  });

  test("an unreadable photo is the recogniser's failure, and nothing after "
      'it runs', () async {
    receipts.answer = const Left(OcrFailure('No text was found.'));

    final result = await read('/cache/blank.jpg');

    expect(
      result.getLeft().toNullable(),
      const OcrFailure('No text was found.'),
    );
    expect(dictionary.lookups, isEmpty);
  });

  test("text with no items and no total is the parser's failure", () async {
    receipts.answer = Right(RecognisedText.fromString('THANK YOU\nCOME AGAIN'));

    final result = await read('/cache/note.jpg');

    expect(result.getLeft().toNullable(), isA<OcrFailure>());
    expect(dictionary.lookups, isEmpty);
  });

  test(
    "a dictionary that cannot be read is the categoriser's failure",
    () async {
      receipts.answer = Right(
        RecognisedText.fromString('SHOP\nRICE 1,250.00\nTOTAL 1,250.00'),
      );
      dictionary.failWith = const CacheFailure('locked');

      final result = await read('/cache/receipt.jpg');

      expect(result.getLeft().toNullable(), const CacheFailure('locked'));
    },
  );

  test('an empty path is refused before the recogniser is asked', () async {
    final result = await read('');

    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    expect(receipts.askedFor, isNull);
  });
}
