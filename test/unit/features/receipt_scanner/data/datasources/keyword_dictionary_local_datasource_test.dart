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

  test('a closed database is a CacheException', () async {
    await db.close();

    expect(() => dictionary.matchesFor('rice'), throwsA(isA<CacheException>()));
  });
}
