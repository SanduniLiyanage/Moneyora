/// The only place SQL is written for the categories feature.
///
/// Throws [CacheException] on failure and returns models; the repository
/// above converts. See `docs/ARCHITECTURE.md` §3.
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/database/database_change_bus.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/category.dart';
import '../models/category_model.dart';

/// Reads and writes categories in the local encrypted database.
abstract interface class CategoryLocalDataSource {
  /// Inserts [category] and returns its new id.
  Future<int> add(CategoryModel category);

  /// Updates the editable columns of [category].
  Future<void> update(CategoryModel category);

  /// Removes the row. Fails if anything still references it.
  Future<void> delete(int id);

  /// Reads one category, or null if [id] does not exist.
  Future<CategoryModel?> find(int id);

  /// How many `transactions` or `transaction_splits` rows cite [id].
  Future<int> usageCount(int id);

  /// How many `categories` rows name [id] as their `parent_id`.
  Future<int> childCount(int id);

  /// Reads categories, in seed/sort order. Both kinds unless [type] narrows
  /// it.
  Future<List<CategoryModel>> list({CategoryType? type});

  /// Fires after every successful write.
  Stream<void> get changes;

  /// Closes [changes].
  Future<void> dispose();
}

/// sqflite implementation of [CategoryLocalDataSource].
class CategoryLocalDataSourceImpl implements CategoryLocalDataSource {
  /// Creates a datasource over an already-open [db].
  CategoryLocalDataSourceImpl(this._db) : _changes = DatabaseChangeBus();

  final Database _db;
  final DatabaseChangeBus _changes;

  @override
  Stream<void> get changes => _changes.changes;

  @override
  Future<void> dispose() => _changes.close();

  void _notify() => _changes.notify();

  @override
  Future<int> add(CategoryModel category) async {
    final id = await _guard(
      'add a category',
      () => _db.insert('categories', category.toMap()),
    );

    _notify();
    return id;
  }

  @override
  Future<void> update(CategoryModel category) async {
    final id = category.id;
    if (id == null) {
      throw const CacheException('Cannot update a category with no id.');
    }

    await _guard('update category $id', () async {
      final changed = await _db.update(
        'categories',
        category.toUpdateMap(),
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed == 0) throw CacheException('No category with id $id.');
    });

    _notify();
  }

  @override
  Future<void> delete(int id) async {
    await _guard('delete category $id', () async {
      // The foreign keys from transactions, transaction_splits and a child
      // category's parent_id would refuse anyway, but failing here says what
      // and how many, rather than quoting a constraint name.
      final used = await usageCount(id);
      if (used > 0) {
        throw CacheException('Category $id is still used by $used rows.');
      }
      final children = await childCount(id);
      if (children > 0) {
        throw CacheException(
          'Category $id still has $children sub-categories.',
        );
      }
      final removed = await _db.delete(
        'categories',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (removed == 0) throw CacheException('No category with id $id.');
    });

    _notify();
  }

  @override
  Future<CategoryModel?> find(int id) => _guard('read category $id', () async {
    final rows = await _db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : CategoryModel.fromMap(rows.first);
  });

  @override
  Future<int> usageCount(int id) => _guard(
    'count usages of category $id',
    () async =>
        (await _db.rawQuery(
              '''
SELECT
  (SELECT COUNT(*) FROM transactions WHERE category_id = ?)
  + (SELECT COUNT(*) FROM transaction_splits WHERE category_id = ?)
  AS c
''',
              [id, id],
            )).first['c']!
            as int,
  );

  @override
  Future<int> childCount(int id) => _guard(
    'count sub-categories of category $id',
    () async =>
        (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM categories WHERE parent_id = ?',
              [id],
            )).first['c']!
            as int,
  );

  @override
  Future<List<CategoryModel>> list({CategoryType? type}) =>
      _guard('read categories', () async {
        final rows = await _db.query(
          'categories',
          where: type == null ? null : 'type = ?',
          whereArgs: type == null ? null : [type.storageValue],
          // Seed order, then name - the list a user sees should not
          // reshuffle itself between launches for no reason they can
          // perceive.
          orderBy: 'sort_order ASC, name ASC',
        );
        return rows.map(CategoryModel.fromMap).toList();
      });

  Future<T> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return await body();
    } on CacheException {
      rethrow;
    } on DatabaseException catch (e) {
      throw CacheException('Could not $action.', cause: e);
    }
  }
}
