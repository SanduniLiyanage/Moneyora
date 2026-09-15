@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/keyword_seed.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/keyword_dictionary_local_datasource.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/keyword_match.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Against a real in-memory SQLite with the real seed, so every claim here
/// is about the lookup the app will run.
void main() {
  sqfliteFfiInit();

  late Database db;
  late KeywordDictionaryLocalDataSourceImpl dictionary;
  late int food;
  late int health;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          final batch = d.batch();
          for (final version in schemaMigrations.keys.toList()..sort()) {
            for (final statement in schemaMigrations[version]!) {
              batch.execute(statement);
            }
          }
          await batch.commit(noResult: true);
        },
        version: latestSchemaVersion,
      ),
    );
    await applyDefaultSeed(db);
    await applyKeywordSeed(db);

    Future<int> idOf(String name) async =>
        (await db.query(
              'categories',
              columns: ['id'],
              where: 'name = ?',
              whereArgs: [name],
            )).single['id']!
            as int;
    food = await idOf('Food');
    health = await idOf('Health');

    dictionary = KeywordDictionaryLocalDataSourceImpl(db);
  });

  tearDown(() => db.close());

  Future<int> teach(
    String keyword,
    int categoryId, {
    String match = 'contains',
  }) => db.insert('keyword_dictionary', {
    'keyword': keyword,
    'category_id': categoryId,
    'match_type': match,
    'priority': 10,
    'is_user_defined': 1,
  });

  test('contains: a seed keyword inside a printed line', () async {
    final matches = await dictionary.matchesFor('RICE 5KG');

    expect(matches.map((m) => m.keyword), ['rice']);
    final m = matches.single;
    expect(m.categoryId, food);
    expect(m.categoryName, 'Food');
    expect(m.matchType, KeywordMatchType.contains);
    expect(m.priority, 5);
    expect(m.isUserDefined, isFalse);
  });

  test('startswith: at the start of the line, not inside a word', () async {
    expect((await dictionary.matchesFor('BUS FARE')).map((m) => m.keyword), [
      'fare',
      'bus',
    ]);
    expect(
      (await dictionary.matchesFor('ROBUST COFFEE')).map((m) => m.keyword),
      ['coffee'],
    );
  });

  test('exact: the whole line and nothing else', () async {
    await teach('lime juice', food, match: 'exact');

    expect(
      (await dictionary.matchesFor('Lime Juice')).map((m) => m.keyword),
      contains('lime juice'),
    );
    expect(
      (await dictionary.matchesFor('1 x LIME JUICE')).map((m) => m.keyword),
      isNot(contains('lime juice')),
    );
  });

  test('is case-insensitive and ignores surrounding whitespace', () async {
    expect(await dictionary.matchesFor('  panadol  '), isNotEmpty);
    expect(await dictionary.matchesFor('PaNaDoL 500MG'), isNotEmpty);
  });

  test('orders by priority, then the longer keyword, then id', () async {
    await teach('rice', health);

    final matches = await dictionary.matchesFor('FRIED RICE');

    expect(matches.map((m) => '${m.keyword}:${m.categoryName}'), [
      'rice:Health', // priority 10
      'fried rice:Eating Out', // longer
      'rice:Food',
    ]);
    expect(matches.first.isUserDefined, isTrue);
  });

  test('a user keyword holding a LIKE wildcard is a literal', () async {
    await teach('50%', food);

    expect((await dictionary.matchesFor('50% OFF')).map((m) => m.keyword), [
      '50%',
    ]);
    expect(await dictionary.matchesFor('500 OFF'), isEmpty);
  });

  test('nothing for nothing', () async {
    expect(await dictionary.matchesFor(''), isEmpty);
    expect(await dictionary.matchesFor('   '), isEmpty);
    expect(await dictionary.matchesFor('ZZZZ'), isEmpty);
  });

  group('learn', () {
    Future<List<Map<String, Object?>>> rowsFor(String keyword) => db.query(
      'keyword_dictionary',
      where: 'keyword = ?',
      whereArgs: [keyword],
      orderBy: 'id ASC',
    );

    test('stores the line as an exact, priority-10 user keyword', () async {
      final stored = await dictionary.learn(
        text: '  SHAMPOO   200ML ',
        categoryId: health,
      );

      expect(stored, 'shampoo 200ml');
      final row = (await rowsFor('shampoo 200ml')).single;
      expect(row['category_id'], health);
      expect(row['match_type'], 'exact');
      expect(row['priority'], 10);
      expect(row['is_user_defined'], 1);
      expect(row['usage_count'], 0);
    });

    test('is what the next scan reads, ahead of the seed', () async {
      // The whole point: Layer 2 decisive on the next receipt.
      expect(
        (await dictionary.matchesFor('RICE 5KG')).single.categoryName,
        'Food',
      );

      await dictionary.learn(text: 'RICE 5KG', categoryId: health);

      final matches = await dictionary.matchesFor('RICE 5KG');
      expect(matches.first.categoryName, 'Health');
      expect(matches.first.isUserDefined, isTrue);
      expect(matches.first.matchType, KeywordMatchType.exact);
    });

    test('a changed mind replaces the earlier lesson', () async {
      Future<int> seedRows() async =>
          (await db.rawQuery(
                'SELECT COUNT(*) AS n FROM keyword_dictionary '
                'WHERE is_user_defined = 0',
              )).single['n']!
              as int;
      final seedBefore = await seedRows();

      await dictionary.learn(text: 'PANADOL 500MG', categoryId: food);
      await dictionary.learn(text: 'PANADOL 500MG', categoryId: health);

      final rows = await rowsFor('panadol 500mg');
      expect(rows, hasLength(1));
      expect(rows.single['category_id'], health);
      expect(rows.single['is_user_defined'], 1);
      // Only the user's own rows are replaced; the seed is never touched.
      expect(await seedRows(), seedBefore);
    });

    test('teaching what the seed already says adds nothing', () async {
      // UNIQUE(keyword, category_id) covers the seed row too: the user
      // agreeing with `rice -> Food` by hand is not a second row, and
      // the seed row keeps its own priority.
      await dictionary.learn(text: 'rice', categoryId: food);

      final rows = await rowsFor('rice');
      expect(rows, hasLength(1));
      expect(rows.single['is_user_defined'], 0);
    });

    test('the same lesson twice is one row, and keeps its count', () async {
      await dictionary.learn(text: 'MILK 1L', categoryId: food);
      await dictionary.recordApplied(text: 'MILK 1L', categoryId: food);
      await dictionary.learn(text: 'milk 1l', categoryId: food);

      final row = (await rowsFor('milk 1l')).single;
      expect(row['usage_count'], 1);
    });

    test('a blank line teaches nothing', () async {
      expect(await dictionary.learn(text: '   ', categoryId: food), isNull);
      expect(await rowsFor(''), isEmpty);
    });

    test('a category that does not exist is a CacheException', () async {
      await expectLater(
        dictionary.learn(text: 'GHOST', categoryId: 999),
        throwsA(isA<CacheException>()),
      );
      expect(await rowsFor('ghost'), isEmpty);
    });
  });

  group('recordApplied', () {
    Future<int> usageOf(String keyword, int categoryId) async =>
        (await db.query(
              'keyword_dictionary',
              columns: ['usage_count'],
              where: 'keyword = ? AND category_id = ?',
              whereArgs: [keyword, categoryId],
            )).single['usage_count']!
            as int;

    test('counts the rows that match the text under the category', () async {
      // The same predicate as the lookup: what matchesFor would have
      // returned for Food is exactly what moves.
      final moved = await dictionary.recordApplied(
        text: 'RICE 5KG',
        categoryId: food,
      );

      expect(moved, 1);
      expect(await usageOf('rice', food), 1);
    });

    test('leaves a matching row that maps elsewhere alone', () async {
      // The user confirmed Health for a line the seed calls Food: the seed
      // row was suggested, not applied.
      await teach('rice', health);

      final moved = await dictionary.recordApplied(
        text: 'FRIED RICE',
        categoryId: health,
      );

      expect(moved, 1);
      expect(await usageOf('rice', health), 1);
      expect(await usageOf('rice', food), 0);
    });

    test('adds up across confirmations', () async {
      await dictionary.recordApplied(text: 'rice', categoryId: food);
      await dictionary.recordApplied(text: 'RICE 1KG', categoryId: food);

      expect(await usageOf('rice', food), 2);
    });

    test('nothing matching is zero, not an error', () async {
      expect(await dictionary.recordApplied(text: 'ZZZZ', categoryId: food), 0);
      expect(await dictionary.recordApplied(text: ' ', categoryId: food), 0);
    });
  });

  test('a closed database is a CacheException', () async {
    await db.close();

    expect(() => dictionary.matchesFor('rice'), throwsA(isA<CacheException>()));
    expect(
      () => dictionary.recordApplied(text: 'rice', categoryId: food),
      throwsA(isA<CacheException>()),
    );
  });
}
