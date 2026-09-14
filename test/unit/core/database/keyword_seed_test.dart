@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/keyword_seed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('the list', () {
    test('has the 200+ entries the DBD promises', () {
      expect(defaultKeywords.length, greaterThanOrEqualTo(200));
    });

    test('names only default categories', () {
      final names = {for (final c in defaultCategories) c.name};
      for (final k in defaultKeywords) {
        expect(names, contains(k.category), reason: k.keyword);
      }
    });

    test('is lower case, trimmed, and free of LIKE wildcards', () {
      for (final k in defaultKeywords) {
        expect(k.keyword, k.keyword.toLowerCase().trim(), reason: k.keyword);
        expect(k.keyword, isNot(contains('%')));
        expect(k.keyword, isNot(contains('_')));
        expect(k.keyword, isNotEmpty);
      }
    });

    test('uses only contains and startswith, the latter for short words', () {
      for (final k in defaultKeywords) {
        expect(
          ['contains', 'startswith'],
          contains(k.match),
          reason: k.keyword,
        );
        if (k.keyword.length <= 3) {
          expect(k.match, 'startswith', reason: k.keyword);
        }
      }
    });

    test('never maps one keyword to the same category twice', () {
      final pairs = {
        for (final k in defaultKeywords) '${k.keyword}|${k.category}',
      };
      expect(pairs.length, defaultKeywords.length);
    });
  });

  group('applyKeywordSeed', () {
    sqfliteFfiInit();

    late Database db;

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
    });

    tearDown(() => db.close());

    Future<int> rows() async =>
        (await db.rawQuery('SELECT COUNT(*) FROM keyword_dictionary'))
                .first
                .values
                .first!
            as int;

    test('writes every entry once, at priority 5, not user-defined', () async {
      final inserted = await applyKeywordSeed(db);

      expect(inserted, defaultKeywords.length);
      expect(await rows(), defaultKeywords.length);
      final odd = await db.query(
        'keyword_dictionary',
        where: 'priority != 5 OR is_user_defined != 0 OR usage_count != 0',
      );
      expect(odd, isEmpty);
    });

    test('is a no-op the second time', () async {
      await applyKeywordSeed(db);

      expect(await applyKeywordSeed(db), 0);
      expect(await rows(), defaultKeywords.length);
    });

    test("leaves the user's own rows alone", () async {
      await applyKeywordSeed(db);
      final health = (await db.query(
        'categories',
        where: 'name = ?',
        whereArgs: ['Health'],
      )).single['id'];
      await db.insert('keyword_dictionary', {
        'keyword': 'healthguard',
        'category_id': health,
        'priority': 10,
        'is_user_defined': 1,
      });

      await applyKeywordSeed(db);

      expect(await rows(), defaultKeywords.length + 1);
    });

    test('skips a keyword whose category the user has deleted', () async {
      await db.delete('categories', where: 'name = ?', whereArgs: ['Pets']);
      final pets = defaultKeywords.where((k) => k.category == 'Pets').length;

      final inserted = await applyKeywordSeed(db);

      expect(inserted, defaultKeywords.length - pets);
    });

    test('a seed keyword goes with its category', () async {
      await applyKeywordSeed(db);

      await db.delete('categories', where: 'name = ?', whereArgs: ['Pets']);

      final pets = defaultKeywords.where((k) => k.category == 'Pets').length;
      expect(await rows(), defaultKeywords.length - pets);
    });
  });
}
