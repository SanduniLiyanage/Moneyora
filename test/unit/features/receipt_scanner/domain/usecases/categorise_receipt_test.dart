import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/categorised_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/category_suggestion.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/keyword_match.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/parsed_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/keyword_dictionary_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/categorise_receipt.dart';

/// Answers from a script keyed by the text looked up, and records the
/// order of the lookups.
class _FakeDictionary implements KeywordDictionaryRepository {
  @override
  Future<Either<Failure, Unit>> learn({
    required String text,
    required int categoryId,
  }) => throw UnimplementedError('learn');

  @override
  Future<Either<Failure, Unit>> recordApplied({
    required String text,
    required int categoryId,
  }) => throw UnimplementedError('recordApplied');

  Map<String, List<KeywordMatch>> script = const {};
  Failure? failWith;
  final lookups = <String>[];

  @override
  Future<Either<Failure, List<KeywordMatch>>> matchesFor(String text) async {
    lookups.add(text);
    if (failWith case final failure?) return Left(failure);
    return Right(script[text] ?? const []);
  }
}

// The DBD's seed ids: Food 7, Health 9, Toiletry 14, Bills 1, Eating Out 5.
KeywordMatch seed(
  String keyword,
  int categoryId,
  String name, {
  KeywordMatchType type = KeywordMatchType.contains,
}) => KeywordMatch(
  keyword: keyword,
  categoryId: categoryId,
  categoryName: name,
  matchType: type,
);

KeywordMatch taught(
  String keyword,
  int categoryId,
  String name, {
  KeywordMatchType type = KeywordMatchType.contains,
}) => KeywordMatch(
  keyword: keyword,
  categoryId: categoryId,
  categoryName: name,
  matchType: type,
  priority: 10,
  isUserDefined: true,
);

final rice = seed('rice', 7, 'Food');
final basmati = seed('basmati', 7, 'Food');
final panadol = seed('panadol', 9, 'Health', type: KeywordMatchType.exact);
final pharmacy = seed('pharmacy', 9, 'Health');
final shampoo = seed('shampoo', 14, 'Toiletry');
final soap = seed('soap', 14, 'Toiletry');
final water = seed('water', 7, 'Food');
final waterBill = seed('water bill', 1, 'Bills');

void main() {
  group('scoreOf', () {
    test('is the kind of match plus twice the priority', () {
      expect(CategoriseReceipt.scoreOf(panadol), 90);
      expect(
        CategoriseReceipt.scoreOf(
          seed('pan', 9, 'Health', type: KeywordMatchType.startsWith),
        ),
        75,
      );
      expect(CategoriseReceipt.scoreOf(rice), 65);
    });

    test('a taught row adds its priority and the history bonus', () {
      expect(CategoriseReceipt.scoreOf(taught('rice', 7, 'Food')), 95);
      expect(
        CategoriseReceipt.scoreOf(
          taught('rice', 7, 'Food', type: KeywordMatchType.exact),
        ),
        120,
      );
    });
  });

  group('bestOf', () {
    test('nothing from nothing', () {
      expect(CategoriseReceipt.bestOf(const []), isNull);
    });

    test('the highest score, whatever the order given', () {
      expect(CategoriseReceipt.bestOf([rice, panadol]), panadol);
      expect(CategoriseReceipt.bestOf([panadol, rice]), panadol);
    });

    test('on a tie the longer keyword, then the first given', () {
      expect(CategoriseReceipt.bestOf([water, waterBill]), waterBill);
      expect(CategoriseReceipt.bestOf([rice, soap]), rice);
      expect(CategoriseReceipt.bestOf([soap, rice]), soap);
    });
  });

  group('suggest', () {
    test('nothing matched and no merchant is none', () {
      expect(CategoriseReceipt.suggest(const []), CategorySuggestion.none);
    });

    test('a seed keyword is Layer 1 at its score', () {
      expect(
        CategoriseReceipt.suggest([rice]),
        const CategorySuggestion(
          categoryId: 7,
          categoryName: 'Food',
          confidence: 65,
          source: SuggestionSource.keyword,
        ),
      );
    });

    test('a taught keyword is Layer 2, and its score is capped at 100', () {
      expect(
        CategoriseReceipt.suggest([
          taught('rice', 7, 'Food', type: KeywordMatchType.exact),
        ]),
        const CategorySuggestion(
          categoryId: 7,
          categoryName: 'Food',
          confidence: 100,
          source: SuggestionSource.userHistory,
        ),
      );
    });

    test('Layer 2 is decisive: a taught contains beats a seed exact, even '
        'with the merchant behind the seed', () {
      final s = CategoriseReceipt.suggest(
        [panadol, taught('panadol', 7, 'Food')],
        merchantCategoryId: 9,
        merchantCategoryName: 'Health',
      );

      expect(s.categoryId, 7);
      expect(s.confidence, 95);
      expect(s.source, SuggestionSource.userHistory);
    });

    test('Layer 3 adds the bias to the merchant\'s category', () {
      // Food 65 against Health 65: the pharmacy decides it.
      final s = CategoriseReceipt.suggest(
        [rice, pharmacy],
        merchantCategoryId: 9,
        merchantCategoryName: 'Health',
      );

      expect(s.categoryId, 9);
      expect(s.confidence, 85);
      expect(s.source, SuggestionSource.keyword);
    });

    test('Layer 3 alone is the merchant\'s category at the bias', () {
      expect(
        CategoriseReceipt.suggest(
          const [],
          merchantCategoryId: 9,
          merchantCategoryName: 'Health',
        ),
        const CategorySuggestion(
          categoryId: 9,
          categoryName: 'Health',
          confidence: CategoriseReceipt.merchantBias,
          source: SuggestionSource.merchant,
        ),
      );
    });

    test('per category the best keyword counts, not the sum', () {
      // Two Food substrings (65 each) against one Health exact (90).
      final s = CategoriseReceipt.suggest([rice, basmati, panadol]);

      expect(s.categoryId, 9);
      expect(s.confidence, 90);
    });

    test('a tie between categories goes to the longer keyword', () {
      final s = CategoriseReceipt.suggest([water, waterBill]);

      expect(s.categoryId, 1);
      expect(s.categoryName, 'Bills');
    });
  });

  group('the use case', () {
    late _FakeDictionary dictionary;
    late CategoriseReceipt categorise;

    const receipt = ParsedReceipt(
      merchantName: 'HEALTHGUARD PHARMACY',
      items: [
        ReceiptLineItem(name: 'PANADOL 500MG', totalPriceCents: 12000),
        ReceiptLineItem(name: 'SHAMPOO 200ML', totalPriceCents: 65000),
        ReceiptLineItem(name: 'COTTON WOOL', totalPriceCents: 30000),
      ],
      totalCents: 107000,
    );

    setUp(() {
      dictionary = _FakeDictionary()
        ..script = {
          'HEALTHGUARD PHARMACY': [pharmacy],
          'PANADOL 500MG': [panadol],
          'SHAMPOO 200ML': [shampoo],
        };
      categorise = CategoriseReceipt(dictionary);
    });

    test('looks the merchant up once and every item once, in order', () async {
      await categorise(receipt);

      expect(dictionary.lookups, [
        'HEALTHGUARD PHARMACY',
        'PANADOL 500MG',
        'SHAMPOO 200ML',
        'COTTON WOOL',
      ]);
    });

    test('suggests every item with the merchant\'s context', () async {
      final result = await categorise(receipt);

      final categorised = result.getOrElse((f) => fail('$f'));
      expect(categorised.receipt, receipt);
      expect(categorised.merchantCategoryId, 9);
      expect(categorised.merchantCategoryName, 'Health');
      expect(categorised.items.map((i) => i.item), receipt.items);
      expect(categorised.items.map((i) => i.suggestion), const [
        // Exact, plus the pharmacy's bias: 90 + 20, capped.
        CategorySuggestion(
          categoryId: 9,
          categoryName: 'Health',
          confidence: 100,
          source: SuggestionSource.keyword,
        ),
        // Toiletry, unbiased.
        CategorySuggestion(
          categoryId: 14,
          categoryName: 'Toiletry',
          confidence: 65,
          source: SuggestionSource.keyword,
        ),
        // Nothing matched: the pharmacy's lead, at low confidence.
        CategorySuggestion(
          categoryId: 9,
          categoryName: 'Health',
          confidence: 20,
          source: SuggestionSource.merchant,
        ),
      ]);
    });

    test('a receipt with no merchant is not looked up for one', () async {
      const nameless = ParsedReceipt(
        items: [ReceiptLineItem(name: 'COTTON WOOL', totalPriceCents: 30000)],
      );

      final result = await categorise(nameless);

      expect(dictionary.lookups, ['COTTON WOOL']);
      final categorised = result.getOrElse((f) => fail('$f'));
      expect(categorised.merchantCategoryId, isNull);
      expect(categorised.items.single.suggestion, CategorySuggestion.none);
    });

    test('no items is a result with no items', () async {
      final result = await categorise(const ParsedReceipt(totalCents: 100));

      expect(result.getOrElse((f) => fail('$f')).items, isEmpty);
    });

    test('the dictionary\'s failure is the result', () async {
      dictionary.failWith = const CacheFailure();

      expect(
        await categorise(receipt),
        const Left<Failure, CategorisedReceipt>(CacheFailure()),
      );
    });
  });
}
