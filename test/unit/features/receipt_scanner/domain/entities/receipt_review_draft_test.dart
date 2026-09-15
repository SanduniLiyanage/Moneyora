import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/categorised_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/category_suggestion.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/parsed_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_review_draft.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/scanned_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/confirm_receipt.dart';

void main() {
  const food = 7;
  const health = 9;
  final today = DateTime(2026, 9, 15, 10, 30);

  const rice = ReceiptLineItem(
    name: 'RICE 5KG',
    totalPriceCents: 125000,
    quantity: 5,
    unitPriceCents: 25000,
  );
  const bread = ReceiptLineItem(name: 'BREAD', totalPriceCents: 30000);
  const panadol = ReceiptLineItem(name: 'PANADOL 10S', totalPriceCents: 15000);

  const riceSuggested = CategorySuggestion(
    categoryId: food,
    categoryName: 'Food',
    confidence: 90,
    source: SuggestionSource.keyword,
  );
  const breadSuggested = CategorySuggestion(
    categoryId: food,
    categoryName: 'Food',
    confidence: 65,
    source: SuggestionSource.keyword,
  );
  const panadolByMerchant = CategorySuggestion(
    categoryId: health,
    categoryName: 'Health',
    confidence: 20,
    source: SuggestionSource.merchant,
  );

  ScannedReceipt scanned({
    List<CategorisedItem> items = const [
      CategorisedItem(item: rice, suggestion: riceSuggested),
      CategorisedItem(item: bread, suggestion: breadSuggested),
      CategorisedItem(item: panadol, suggestion: panadolByMerchant),
    ],
    DateTime? receiptDate,
    int? totalCents = 170000,
  }) => ScannedReceipt(
    imagePath: '/receipts/keells.jpg',
    receipt: CategorisedReceipt(
      receipt: ParsedReceipt(
        merchantName: 'KEELLS SUPER',
        receiptDate: receiptDate,
        items: [for (final i in items) i.item],
        totalCents: totalCents,
        taxCents: 12000,
        receiptNumber: 'INV-0042',
      ),
      items: items,
      merchantCategoryId: health,
      merchantCategoryName: 'Health',
    ),
  );

  ReceiptReviewDraft draft({DateTime? receiptDate, int? totalCents = 170000}) =>
      ReceiptReviewDraft.fromScanned(
        scanned(receiptDate: receiptDate, totalCents: totalCents),
        today: today,
      );

  group('opening', () {
    test('accepts every suggestion, keys the lines in order, and carries '
        'the header through', () {
      final d = draft();

      expect(d.imagePath, '/receipts/keells.jpg');
      expect(d.merchantName, 'KEELLS SUPER');
      expect(d.totalCents, 170000);
      expect(d.taxCents, 12000);
      expect(d.receiptNumber, 'INV-0042');
      expect(d.merchantCategoryName, 'Health');
      expect(d.accountId, isNull);
      expect(d.items.map((i) => i.key), [0, 1, 2]);
      expect(d.items.map((i) => i.categoryId), [food, food, health]);
      expect(d.nextKey, 3);
    });

    test('posts on the receipt date when one was read, else today, '
        'without a time', () {
      expect(
        draft(receiptDate: DateTime(2026, 4, 3, 14, 20)).postedOn,
        DateTime(2026, 4, 3),
      );
      expect(draft().postedOn, DateTime(2026, 9, 15));
    });

    test('a line nothing matched has no category', () {
      final d = ReceiptReviewDraft.fromScanned(
        scanned(
          items: const [
            CategorisedItem(item: bread, suggestion: CategorySuggestion.none),
          ],
        ),
        today: today,
      );
      expect(d.items.single.categoryId, isNull);
      expect(d.uncategorisedCount, 1);
    });
  });

  group('the figures', () {
    test('sum the kept lines and check them against the total', () {
      expect(draft().itemsSumCents, 170000);
      expect(draft().itemsMatchTotal, isTrue);
      expect(draft().discard(1).itemsMatchTotal, isFalse);
      expect(draft(totalCents: null).itemsMatchTotal, isNull);
    });

    test('badge the merchant-only line and not the keyword ones '
        '(FR-RCP-011)', () {
      final d = draft();
      expect(d.items[0].isLowConfidence, isFalse);
      expect(d.items[1].isLowConfidence, isFalse);
      expect(d.items[2].isLowConfidence, isTrue);
    });

    test('the receipt is low confidence only when the mean is', () {
      final d = draft();
      expect(d.meanConfidence, 58);
      expect(d.isLowConfidence, isFalse);
      expect(d.discard(0).discard(1).isLowConfidence, isTrue);
      expect(d.discard(0).discard(1).discard(2).isLowConfidence, isFalse);
    });
  });

  group('editing a line', () {
    test('renames it and keeps its figures', () {
      final d = draft().rename(0, 'Basmati rice');
      expect(d.items[0].item.name, 'Basmati rice');
      expect(d.items[0].item.totalPriceCents, 125000);
      expect(d.items[0].item.quantity, 5);
      expect(d.items[0].item.unitPriceCents, 25000);
      expect(d.items[0].key, 0);
    });

    test('reprices it and drops the unit price that no longer holds', () {
      final d = draft().reprice(0, 120000);
      expect(d.items[0].item.totalPriceCents, 120000);
      expect(d.items[0].item.unitPriceCents, isNull);
      expect(d.items[0].item.quantity, 5);
    });

    test('recategorises it and remembers what was suggested', () {
      final d = draft().recategorise(2, food);
      expect(d.items[2].categoryId, food);
      expect(d.items[2].suggestion, panadolByMerchant);
    });

    test('unsets a category the catalogue no longer has, keeping the '
        'suggestion', () {
      final d = draft().keepingCategories([food]);
      expect(d.items[2].categoryId, isNull);
      expect(d.items[2].suggestion, panadolByMerchant);
      expect(d.items[0].categoryId, food);
      expect(d.uncategorisedCount, 1);
      // Nothing to unset: the same draft, not a copy.
      final same = draft();
      expect(identical(same.keepingCategories([food, health]), same), isTrue);
    });

    test('discards it', () {
      final d = draft().discard(1);
      expect(d.items.map((i) => i.item.name), ['RICE 5KG', 'PANADOL 10S']);
      expect(d.items.map((i) => i.key), [0, 2]);
    });
  });

  group('merging', () {
    test('joins a line with the one below into one purchase under a new '
        'key, keeping the upper suggestion', () {
      final d = draft().mergeWithNext(0);

      expect(d.items.length, 2);
      final merged = d.items[0];
      expect(merged.key, 3);
      expect(merged.item.name, 'RICE 5KG + BREAD');
      expect(merged.item.totalPriceCents, 155000);
      expect(merged.item.quantity, 1);
      expect(merged.item.unitPriceCents, isNull);
      expect(merged.suggestion, riceSuggested);
      expect(merged.categoryId, food);
      expect(d.items[1].key, 2);
      expect(d.nextKey, 4);
    });

    test('two lines of the same name keep the name', () {
      final d = ReceiptReviewDraft.fromScanned(
        scanned(
          items: const [
            CategorisedItem(item: bread, suggestion: breadSuggested),
            CategorisedItem(item: bread, suggestion: breadSuggested),
          ],
        ),
        today: today,
      ).mergeWithNext(0);
      expect(d.items.single.item.name, 'BREAD');
      expect(d.items.single.item.totalPriceCents, 60000);
    });

    test('takes the lower category when the upper line had none', () {
      final d = ReceiptReviewDraft.fromScanned(
        scanned(
          items: const [
            CategorisedItem(item: bread, suggestion: CategorySuggestion.none),
            CategorisedItem(item: rice, suggestion: riceSuggested),
          ],
        ),
        today: today,
      ).mergeWithNext(0);
      expect(d.items.single.categoryId, food);
      expect(d.items.single.suggestion, CategorySuggestion.none);
    });

    test('the last line has nothing to merge with', () {
      expect(draft().canMergeWithNext(2), isFalse);
      expect(draft().canMergeWithNext(1), isTrue);
      expect(draft().canMergeWithNext(99), isFalse);
    });
  });

  group('splitting', () {
    test('cuts a line into two under new keys, both carrying the name, '
        'the suggestion and the category', () {
      final d = draft().split(0, 100000);

      expect(d.items.length, 4);
      expect(d.items[0].key, 3);
      expect(d.items[1].key, 4);
      expect(d.items[0].item.totalPriceCents, 100000);
      expect(d.items[1].item.totalPriceCents, 25000);
      for (final part in d.items.take(2)) {
        expect(part.item.name, 'RICE 5KG');
        expect(part.item.quantity, 1);
        expect(part.item.unitPriceCents, isNull);
        expect(part.suggestion, riceSuggested);
        expect(part.categoryId, food);
      }
      expect(d.items[2].key, 1);
      expect(d.itemsSumCents, 170000);
      expect(d.nextKey, 5);
    });

    test('at zero or at the whole amount is not a split', () {
      expect(ReceiptReviewDraft.canSplit(rice, 0), isFalse);
      expect(ReceiptReviewDraft.canSplit(rice, 125000), isFalse);
      expect(ReceiptReviewDraft.canSplit(rice, 1), isTrue);
      expect(ReceiptReviewDraft.canSplit(rice, 124999), isTrue);
    });
  });

  group('the header', () {
    test('merchant is trimmed, and blank is none', () {
      expect(draft().withMerchant('  Keells  ').merchantName, 'Keells');
      expect(draft().withMerchant('   ').merchantName, isNull);
      expect(draft().withMerchant(null).merchantName, isNull);
    });

    test('the posting day drops any time', () {
      expect(
        draft().withPostedOn(DateTime(2026, 9, 1, 23, 59)).postedOn,
        DateTime(2026, 9, 1),
      );
    });
  });

  group('handing over', () {
    test('is refused without an account, then without a category', () {
      final noAccount = ReceiptReviewDraft.fromScanned(
        scanned(
          items: const [
            CategorisedItem(item: bread, suggestion: CategorySuggestion.none),
          ],
        ),
        today: today,
      );
      expect(noAccount.unfinished, 'Choose an account.');
      expect(noAccount.toReviewed(), isNull);

      final noCategory = noAccount.withAccount(1);
      expect(noCategory.unfinished, 'Choose a category for every item.');
      expect(noCategory.toReviewed(), isNull);

      final done = noCategory.recategorise(0, food);
      expect(done.unfinished, isNull);
      expect(done.toReviewed(), isNotNull);
    });

    test('builds the reviewed receipt ConfirmReceipt takes', () {
      final reviewed = draft(receiptDate: DateTime(2026, 4, 3, 14, 20))
          .withAccount(1)
          .recategorise(2, food)
          .reprice(1, 35000)
          .toReviewed()!;

      expect(reviewed.imagePath, '/receipts/keells.jpg');
      expect(reviewed.accountId, 1);
      expect(reviewed.postedOn, DateTime(2026, 4, 3));
      expect(reviewed.receiptDate, DateTime(2026, 4, 3, 14, 20));
      expect(reviewed.merchantName, 'KEELLS SUPER');
      expect(reviewed.totalCents, 170000);
      expect(reviewed.taxCents, 12000);
      expect(reviewed.receiptNumber, 'INV-0042');
      expect(reviewed.items.length, 3);
      expect(reviewed.items[1].item.totalPriceCents, 35000);
      expect(reviewed.items[2].categoryId, food);
      expect(reviewed.items[2].suggestedCategoryId, health);
      expect(reviewed.items[2].confidence, 20);
      expect(reviewed.items[2].needsLearning, isTrue);
      expect(reviewed.items[0].needsLearning, isFalse);
      expect(ConfirmReceipt.validate(reviewed), isNull);
      expect(
        ConfirmReceipt.meanConfidence(reviewed.items),
        draft().meanConfidence,
      );
    });

    test('an empty draft hands over a receipt validate refuses', () {
      final reviewed = draft()
          .withAccount(1)
          .discard(0)
          .discard(1)
          .discard(2)
          .toReviewed()!;
      expect(reviewed.items, isEmpty);
      expect(
        ConfirmReceipt.validate(reviewed)?.message,
        'Keep at least one item.',
      );
    });
  });
}
