import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/keyword_dictionary_local_datasource.dart';
import 'package:moneyora/features/receipt_scanner/data/models/keyword_match_model.dart';
import 'package:moneyora/features/receipt_scanner/data/repositories/keyword_dictionary_repository_impl.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/keyword_match.dart';

class _FakeLocal implements KeywordDictionaryLocalDataSource {
  List<KeywordMatchModel> rows = const [];
  AppException? throwWith;

  @override
  Future<List<KeywordMatchModel>> matchesFor(String text) async {
    if (throwWith case final e?) throw e;
    return rows;
  }
}

void main() {
  late _FakeLocal local;
  late KeywordDictionaryRepositoryImpl repository;

  setUp(() {
    local = _FakeLocal();
    repository = KeywordDictionaryRepositoryImpl(local);
  });

  test('returns the rows as entities', () async {
    local.rows = const [
      KeywordMatchModel(
        keyword: 'rice',
        categoryId: 7,
        categoryName: 'Food',
        matchType: KeywordMatchType.contains,
      ),
    ];

    final result = await repository.matchesFor('RICE 5KG');

    final matches = result.getOrElse((f) => fail('$f'));
    expect(matches, hasLength(1));
    expect(matches.single.keyword, 'rice');
    expect(matches.single.categoryId, 7);
    expect(matches.single.categoryName, 'Food');
    expect(matches.single.matchType, KeywordMatchType.contains);
  });

  test('a CacheException is a CacheFailure', () async {
    local.throwWith = const CacheException('Could not look up "x".');

    expect(
      await repository.matchesFor('x'),
      const Left<Failure, List<KeywordMatch>>(
        CacheFailure('Could not look up "x".'),
      ),
    );
  });

  test('the model maps every match type both ways', () {
    for (final type in KeywordMatchType.values) {
      expect(
        KeywordMatchModel.decodeMatchType(
          KeywordMatchModel.encodeMatchType(type),
        ),
        type,
      );
    }
    expect(
      KeywordMatchModel.encodeMatchType(KeywordMatchType.startsWith),
      'startswith',
    );
    expect(
      () => KeywordMatchModel.decodeMatchType('regex'),
      throwsArgumentError,
    );
  });

  test('the model reads a joined row', () {
    final m = KeywordMatchModel.fromMap(const {
      'keyword': 'panadol',
      'category_id': 9,
      'category_name': 'Health',
      'match_type': 'exact',
      'priority': 10,
      'is_user_defined': 1,
    });

    expect(m.matchType, KeywordMatchType.exact);
    expect(m.priority, 10);
    expect(m.isUserDefined, isTrue);
    expect(m.categoryName, 'Health');
  });
}
