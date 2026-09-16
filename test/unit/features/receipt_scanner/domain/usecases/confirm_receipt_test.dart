import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/expense_writer.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/keyword_match.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/reviewed_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/keyword_dictionary_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/confirm_receipt.dart';

/// Records every call in the order it arrived, so the tests can state the
/// one thing the use case is really about: what has been written by the
/// time something fails.
class _Log {
  final List<String> calls = [];
}

class _FakeReceipts implements ReceiptRepository {
  @override
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory() =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source) =>
      throw UnimplementedError();

  _FakeReceipts(this._log);

  final _Log _log;
  ReceiptScan? saved;
  Either<Failure, int> result = const Right(42);
  String? kept;
  Either<Failure, String> keepResult = const Right(
    '/documents/receipts/a1b2.jpg.enc',
  );

  @override
  Future<Either<Failure, String>> keepImage(String imagePath) async {
    _log.calls.add('keep');
    kept = imagePath;
    return keepResult;
  }

  @override
  Future<Either<Failure, Uint8List?>> loadImage(String imagePath) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan) async {
    _log.calls.add('scan');
    saved = scan;
    return result;
  }

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) =>
      throw UnimplementedError();
}

class _FakeDictionary implements KeywordDictionaryRepository {
  _FakeDictionary(this._log);

  final _Log _log;
  final List<(String, int)> applied = [];
  final List<(String, int)> learnt = [];
  Either<Failure, Unit> result = const Right(unit);
  Either<Failure, Unit> learnResult = const Right(unit);

  @override
  Future<Either<Failure, Unit>> learn({
    required String text,
    required int categoryId,
  }) async {
    _log.calls.add('learn');
    learnt.add((text, categoryId));
    return learnResult;
  }

  @override
  Future<Either<Failure, Unit>> recordApplied({
    required String text,
    required int categoryId,
  }) async {
    _log.calls.add('count');
    applied.add((text, categoryId));
    return result;
  }

  @override
  Future<Either<Failure, List<KeywordMatch>>> matchesFor(String text) =>
      throw UnimplementedError();
}

class _FakeExpenses implements ExpenseWriter {
  _FakeExpenses(this._log);

  final _Log _log;
  List<ExpenseToRecord>? posted;
  Either<Failure, List<int>> result = const Right([]);

  @override
  Future<Either<Failure, List<int>>> call(
    List<ExpenseToRecord> expenses,
  ) async {
    _log.calls.add('post');
    posted = expenses;
    return result;
  }
}

void main() {
  late _Log log;
  late _FakeReceipts receipts;
  late _FakeDictionary dictionary;
  late _FakeExpenses expenses;
  late ConfirmReceipt confirm;

  const food = 7;
  const toiletry = 9;
  final postedOn = DateTime(2026, 4, 3);

  const rice = ReviewedItem(
    item: ReceiptLineItem(name: 'RICE 5KG', totalPriceCents: 125000),
    categoryId: food,
    suggestedCategoryId: food,
    confidence: 90,
  );
  const shampoo = ReviewedItem(
    item: ReceiptLineItem(name: 'SHAMPOO 200ML', totalPriceCents: 65000),
    categoryId: toiletry,
    suggestedCategoryId: food,
    confidence: 40,
  );

  ReviewedReceipt receipt({
    List<ReviewedItem> items = const [rice, shampoo],
    String imagePath = '/receipts/keells.jpg',
    String? merchantName = 'KEELLS SUPER',
    DateTime? receiptDate,
    DateTime? on,
  }) => ReviewedReceipt(
    imagePath: imagePath,
    accountId: 1,
    postedOn: on ?? postedOn,
    items: items,
    merchantName: merchantName,
    receiptDate: receiptDate ?? DateTime(2026, 4, 3, 14, 32),
    totalCents: 190000,
    taxCents: 0,
    receiptNumber: '4521',
  );

  setUp(() {
    log = _Log();
    receipts = _FakeReceipts(log);
    dictionary = _FakeDictionary(log);
    expenses = _FakeExpenses(log)..result = const Right([10, 11]);
    confirm = ConfirmReceipt(receipts, dictionary, expenses);
  });

  group('the happy path', () {
    test('returns the scan id and one transaction per item', () async {
      final result = await confirm(receipt());

      expect(
        result,
        const Right<Failure, ReceiptConfirmation>(
          ReceiptConfirmation(scanId: 42, transactionIds: [10, 11]),
        ),
      );
    });

    test('keeps the photo, and the scan points at the kept copy, not the '
        "picker's file (FR-RCP-012)", () async {
      await confirm(receipt());

      expect(receipts.kept, '/receipts/keells.jpg');
      expect(receipts.saved!.imagePath, '/documents/receipts/a1b2.jpg.enc');
    });

    test('stores the scan as confirmed, with every kept line', () async {
      await confirm(receipt());

      final scan = receipts.saved!;
      expect(scan.status, ReceiptScanStatus.confirmed);
      expect(scan.merchantName, 'KEELLS SUPER');
      expect(scan.receiptDate, DateTime(2026, 4, 3, 14, 32));
      expect(scan.totalCents, 190000);
      expect(scan.receiptNumber, '4521');
      expect(scan.confidence, 65); // the mean of 90 and 40
      expect(scan.items.map((i) => i.item.name), ['RICE 5KG', 'SHAMPOO 200ML']);
      expect(scan.items.map((i) => i.suggestedCategoryId), [food, food]);
      expect(scan.items.map((i) => i.confirmedCategoryId), [food, toiletry]);
      expect(scan.items.map((i) => i.confidence), [90, 40]);
    });

    test('posts one expense per item, linked to the scan', () async {
      await confirm(receipt());

      final posted = expenses.posted!;
      expect(posted, hasLength(2));
      expect(posted.map((e) => e.amountCents), [125000, 65000]);
      expect(posted.map((e) => e.categoryId), [food, toiletry]);
      for (final e in posted) {
        expect(e.accountId, 1);
        expect(e.date, postedOn);
        expect(e.time, '14:32');
        expect(e.receiptScanId, 42);
        expect(e.receiptImagePath, '/documents/receipts/a1b2.jpg.enc');
      }
    });

    test('the note is the item and, in brackets, the merchant', () async {
      await confirm(receipt());
      expect(expenses.posted!.first.note, 'RICE 5KG (KEELLS SUPER)');

      await confirm(receipt(merchantName: null));
      expect(expenses.posted!.first.note, 'RICE 5KG');

      await confirm(receipt(merchantName: '  '));
      expect(expenses.posted!.first.note, 'RICE 5KG');

      // FR-RCP-010's one line is named after the merchant; no bracket.
      await confirm(
        receipt(
          items: const [
            ReviewedItem(
              item: ReceiptLineItem(
                name: 'KEELLS SUPER',
                totalPriceCents: 190000,
              ),
              categoryId: food,
            ),
          ],
        ),
      );
      expect(expenses.posted!.first.note, 'KEELLS SUPER');
    });

    test('a receipt with only a date carries no time', () async {
      await confirm(receipt(receiptDate: DateTime(2026, 4, 3)));

      expect(expenses.posted!.first.time, isNull);
    });

    test('counts a use of the mapping the user agreed with, per item', () {
      // The categoriser writes nothing; this is the one place usage_count
      // moves. The shampoo line is counted under Toiletry — what the user
      // chose — not under Food, which was only suggested.
      return confirm(receipt()).then((_) {
        expect(dictionary.applied, [
          ('RICE 5KG', food),
          ('SHAMPOO 200ML', toiletry),
        ]);
      });
    });

    test(
      'teaches the dictionary every line the user categorised differently',
      () async {
        // Rice kept the suggestion: nothing to learn. Shampoo was corrected
        // from Food to Toiletry: learnt. A line with no suggestion at all,
        // categorised by hand, is learnt too — it is a change from nothing.
        const unsuggested = ReviewedItem(
          item: ReceiptLineItem(name: 'GIFT WRAP', totalPriceCents: 30000),
          categoryId: 11,
        );

        await confirm(receipt(items: const [rice, shampoo, unsuggested]));

        expect(dictionary.learnt, [
          ('SHAMPOO 200ML', toiletry),
          ('GIFT WRAP', 11),
        ]);
      },
    );

    test('keeps the photo, writes the record, then per line the lesson '
        'and the count, then the expenses', () async {
      await confirm(receipt());

      // rice: count only. shampoo: learn, then count — so the correction
      // is counted as applied on the line that taught it.
      expect(log.calls, ['keep', 'scan', 'count', 'learn', 'count', 'post']);
    });
  });

  group('what is refused before anything is written', () {
    Future<void> expectRefused(ReviewedReceipt r, String message) async {
      final result = await confirm(r);

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(
          f,
          isA<ValidationFailure>().having(
            (f) => f.message,
            'message',
            contains(message),
          ),
        ),
        (_) {},
      );
      expect(log.calls, isEmpty);
    }

    test('no items', () => expectRefused(receipt(items: const []), 'one item'));

    test('an item with no name', () async {
      await expectRefused(
        receipt(
          items: const [
            rice,
            ReviewedItem(
              item: ReceiptLineItem(name: '  ', totalPriceCents: 100),
              categoryId: food,
            ),
          ],
        ),
        'Item 2 needs a name',
      );
    });

    test('an item with no amount', () async {
      await expectRefused(
        receipt(
          items: const [
            ReviewedItem(
              item: ReceiptLineItem(name: 'BREAD', totalPriceCents: 0),
              categoryId: food,
            ),
          ],
        ),
        'Item 1 needs an amount',
      );
    });

    test('no photo', () => expectRefused(receipt(imagePath: ''), 'photo'));

    test('a date in the future', () async {
      await expectRefused(
        receipt(on: DateTime.now().add(const Duration(days: 30))),
        'future',
      );
    });

    test('validate is the same rule the screen can ask', () {
      expect(ConfirmReceipt.validate(receipt()), isNull);
      expect(
        ConfirmReceipt.validate(receipt(items: const [])),
        isA<ValidationFailure>(),
      );
    });
  });

  group('what fails midway', () {
    test('the photo failing to be kept writes nothing', () async {
      receipts.keepResult = const Left(EncryptionFailure('no key'));

      final result = await confirm(receipt());

      expect(
        result,
        const Left<Failure, ReceiptConfirmation>(EncryptionFailure('no key')),
      );
      expect(log.calls, ['keep']);
      expect(receipts.saved, isNull);
      expect(expenses.posted, isNull);
    });

    test('the record failing posts nothing', () async {
      receipts.result = const Left(CacheFailure());

      final result = await confirm(receipt());

      expect(result, const Left<Failure, ReceiptConfirmation>(CacheFailure()));
      expect(log.calls, ['keep', 'scan']);
      expect(expenses.posted, isNull);
    });

    test('a lesson failing posts nothing', () async {
      dictionary.learnResult = const Left(CacheFailure());

      final result = await confirm(receipt());

      expect(result, const Left<Failure, ReceiptConfirmation>(CacheFailure()));
      expect(log.calls, ['keep', 'scan', 'count', 'learn']);
      expect(expenses.posted, isNull);
    });

    test('a count failing posts nothing', () async {
      // Money has not moved yet, so the failure is returned and a retry
      // costs a stray scan record, never a second set of expenses.
      dictionary.result = const Left(CacheFailure());

      final result = await confirm(receipt());

      expect(result, const Left<Failure, ReceiptConfirmation>(CacheFailure()));
      expect(log.calls, ['keep', 'scan', 'count']);
      expect(expenses.posted, isNull);
    });

    test('the expenses failing returns that failure', () async {
      expenses.result = const Left(
        ValidationFailure('Item 2: Enter an amount greater than zero.'),
      );

      final result = await confirm(receipt());

      expect(result.isLeft(), isTrue);
      expect(log.calls, ['keep', 'scan', 'count', 'learn', 'count', 'post']);
    });
  });

  test('needsLearning: a kept suggestion is not news, anything else is', () {
    expect(rice.needsLearning, isFalse);
    expect(shampoo.needsLearning, isTrue);
    expect(
      const ReviewedItem(
        item: ReceiptLineItem(name: 'X', totalPriceCents: 1),
        categoryId: 1,
      ).needsLearning,
      isTrue,
    );
  });

  test('the mean confidence rounds and reads 0 for nothing', () {
    expect(ConfirmReceipt.meanConfidence(const []), 0);
    expect(
      ConfirmReceipt.meanConfidence(const [
        ReviewedItem(
          item: ReceiptLineItem(name: 'A', totalPriceCents: 1),
          categoryId: 1,
          confidence: 100,
        ),
        ReviewedItem(
          item: ReceiptLineItem(name: 'B', totalPriceCents: 1),
          categoryId: 1,
          confidence: 50,
        ),
        ReviewedItem(
          item: ReceiptLineItem(name: 'C', totalPriceCents: 1),
          categoryId: 1,
          confidence: 50,
        ),
      ]),
      67,
    );
  });
}
