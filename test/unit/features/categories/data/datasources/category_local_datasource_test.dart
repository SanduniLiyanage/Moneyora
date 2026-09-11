@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/categories/data/datasources/category_local_datasource.dart';
import 'package:moneyora/features/categories/data/models/category_model.dart';
import 'package:moneyora/features/categories/domain/entities/category.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Against a real in-memory SQLite, because `usageCount` and `childCount`
/// are claims about what two other tables hold, not about this file's own
/// arithmetic.
void main() {
  sqfliteFfiInit();

  late Database db;
  late CategoryLocalDataSourceImpl categories;

  const food = 1;
  const salary = 2;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          final batch = d.batch();
          for (final statement in v1Statements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        },
        version: v1SchemaVersion,
      ),
    );

    const now = '2026-01-01T00:00:00Z';
    await db.insert('users', {'id': 1, 'created_at': now});
    await db.insert('accounts', {
      'id': 1,
      'user_id': 1,
      'name': 'Cash',
      'icon': 'wallet',
      'initial_balance_date': '2026-01-01',
      'created_at': now,
    });
    for (final (id, name, type) in [
      (food, 'Food', 'expense'),
      (salary, 'Salary', 'income'),
    ]) {
      await db.insert('categories', {
        'id': id,
        'user_id': 1,
        'name': name,
        'icon': 'dot',
        'color': '#3F51B5',
        'type': type,
      });
    }

    categories = CategoryLocalDataSourceImpl(db);
  });

  tearDown(() async {
    await categories.dispose();
    await db.close();
  });

  CategoryModel model({
    String name = 'Groceries',
    CategoryType type = CategoryType.expense,
    int? parentId,
    int? id,
  }) => CategoryModel(
    id: id,
    name: name,
    icon: 'basket',
    colorHex: '#FF9800',
    type: type,
    parentId: parentId,
  );

  group('add', () {
    test('stores the category and it can be read back', () async {
      final id = await categories.add(model());

      final read = await categories.find(id);
      expect(read?.name, 'Groceries');
      expect(read?.colorHex, '#FF9800');
    });

    test('round-trips the type through its storage string', () async {
      final id = await categories.add(model(type: CategoryType.income));

      final read = await categories.find(id);
      expect(read?.type, CategoryType.income);
    });

    test('accepts a parent id', () async {
      final id = await categories.add(model(parentId: food));

      final read = await categories.find(id);
      expect(read?.parentId, food);
    });
  });

  group('update', () {
    test('changes the editable fields', () async {
      final id = await categories.add(model());

      await categories.update(model(id: id, name: 'Renamed'));

      expect((await categories.find(id))?.name, 'Renamed');
    });

    test('refuses an id that is not there', () async {
      expect(
        () => categories.update(model(id: 4242)),
        throwsA(isA<CacheException>()),
      );
    });
  });

  group('find', () {
    test('returns null for an id that does not exist', () async {
      expect(await categories.find(4242), isNull);
    });
  });

  group('delete', () {
    test('removes a category nothing references', () async {
      final id = await categories.add(model());

      await categories.delete(id);

      expect(await categories.find(id), isNull);
    });

    test('refuses once a transaction cites it, and says how many', () async {
      await db.insert('transactions', {
        'account_id': 1,
        'category_id': food,
        'amount_cents': 500,
        'type': 'expense',
        'date': '2026-01-02',
        'created_at': '2026-01-02T00:00:00Z',
        'updated_at': '2026-01-02T00:00:00Z',
      });

      await expectLater(
        categories.delete(food),
        throwsA(
          isA<CacheException>().having(
            (e) => e.message,
            'message',
            contains('used by 1 rows'),
          ),
        ),
      );
      expect(await categories.find(food), isNotNull);
    });

    test('refuses once a sub-category is parented under it', () async {
      await categories.add(model(parentId: food));

      await expectLater(
        categories.delete(food),
        throwsA(
          isA<CacheException>().having(
            (e) => e.message,
            'message',
            contains('1 sub-categories'),
          ),
        ),
      );
    });
  });

  group('usageCount', () {
    test('is zero for a fresh category', () async {
      expect(await categories.usageCount(food), 0);
    });

    test('counts transaction_splits rows too', () async {
      await db.insert('transactions', {
        'account_id': 1,
        'category_id': food,
        'amount_cents': 1000,
        'type': 'expense',
        'is_split': 1,
        'date': '2026-01-02',
        'created_at': '2026-01-02T00:00:00Z',
        'updated_at': '2026-01-02T00:00:00Z',
      });
      final txId = (await db.query('transactions')).first['id']! as int;
      await db.insert('transaction_splits', {
        'transaction_id': txId,
        'category_id': salary,
        'amount_cents': 300,
      });

      expect(await categories.usageCount(food), 1);
      expect(await categories.usageCount(salary), 1);
    });
  });

  group('childCount', () {
    test('is zero with no sub-categories', () async {
      expect(await categories.childCount(food), 0);
    });

    test('counts categories parented under it', () async {
      await categories.add(model(parentId: food));
      await categories.add(model(name: 'Snacks', parentId: food));

      expect(await categories.childCount(food), 2);
    });
  });

  group('list', () {
    test('reads both kinds in sort order, then name', () async {
      final read = await categories.list();

      expect(read.map((c) => c.name), ['Food', 'Salary']);
    });

    test('narrows to one type', () async {
      final read = await categories.list(type: CategoryType.income);

      expect(read.map((c) => c.id), [salary]);
    });
  });

  group('changes', () {
    test('fires on every successful write', () async {
      final seen = <void>[];
      final subscription = categories.changes.listen(seen.add);

      final id = await categories.add(model());
      await categories.update(model(id: id, name: 'Renamed'));
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      await subscription.cancel();
    });

    test('stays quiet when a write fails', () async {
      final seen = <void>[];
      final subscription = categories.changes.listen(seen.add);

      await expectLater(
        categories.update(model(id: 4242)),
        throwsA(isA<CacheException>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
      await subscription.cancel();
    });
  });
}
