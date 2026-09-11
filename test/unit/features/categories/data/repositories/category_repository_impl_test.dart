import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/categories/data/datasources/category_local_datasource.dart';
import 'package:moneyora/features/categories/data/models/category_model.dart';
import 'package:moneyora/features/categories/data/repositories/category_repository_impl.dart';
import 'package:moneyora/features/categories/domain/entities/category.dart';

/// The repository translates and nothing else, so these tests are about
/// translation: exceptions becoming failures, models becoming entities, and a
/// watch stream that can actually be cancelled - the same shape as
/// `account_repository_impl_test.dart`.
void main() {
  late _FakeLocalDataSource local;
  late CategoryRepositoryImpl repository;

  Category category({int? id = 1, String name = 'Food'}) => Category(
    id: id,
    name: name,
    icon: 'basket',
    colorHex: '#FF9800',
    type: CategoryType.expense,
  );

  Future<void> settle() async {
    for (var turn = 0; turn < 5; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    local = _FakeLocalDataSource();
    repository = CategoryRepositoryImpl(local);
  });

  tearDown(() => local.dispose());

  group('writes', () {
    test('add returns the new id', () async {
      local.nextId = 4;

      expect(
        await repository.add(category(id: null)),
        const Right<Failure, int>(4),
      );
      expect(local.added.single, isA<CategoryModel>());
    });

    test('update and delete return unit', () async {
      expect(
        await repository.update(category()),
        const Right<Failure, Unit>(unit),
      );
      expect(await repository.delete(1), const Right<Failure, Unit>(unit));
      expect(local.deletedId, 1);
    });

    test('a thrown exception becomes a Left, never an escape', () async {
      local.failWith = const CacheException('database is locked');

      final result = await repository.add(category(id: null));

      expect(
        result,
        const Left<Failure, int>(CacheFailure('database is locked')),
      );
    });
  });

  group('reads', () {
    test('list returns plain entities, not models', () async {
      // Equatable compares runtimeType, so a model handed upward would never
      // equal an identical entity.
      local.rows = [CategoryModel.fromEntity(category())];

      final rows = (await repository.list()).getOrElse((_) => []);

      expect(rows.single.runtimeType, Category);
      expect(rows.single, category());
    });

    test('passes the type filter through', () async {
      await repository.list(type: CategoryType.income);

      expect(local.lastType, CategoryType.income);
    });

    test('find converts a model to an entity, or forwards null', () async {
      local.found = CategoryModel.fromEntity(category());
      expect(
        (await repository.find(1)).getOrElse((_) => null)?.runtimeType,
        Category,
      );

      local.found = null;
      expect(await repository.find(1), const Right<Failure, Category?>(null));
    });

    test('usageCount and childCount forward the number', () async {
      local
        ..usage = 3
        ..children = 2;

      expect(await repository.usageCount(1), const Right<Failure, int>(3));
      expect(await repository.childCount(1), const Right<Failure, int>(2));
    });
  });

  group('watch', () {
    test('emits once immediately, then on every change', () async {
      final seen = <int>[];
      final subscription = repository.watch().listen(
        (either) => seen.add(either.getOrElse((_) => []).length),
      );

      await settle();
      local
        ..rows = [CategoryModel.fromEntity(category())]
        ..emitChange();
      await settle();

      expect(seen, [0, 1]);
      await subscription.cancel();
    });

    test('cancelling completes, and stops the reads', () async {
      var reads = 0;
      local.onList = () => reads++;

      final subscription = repository.watch().listen((_) {});
      await settle();

      await subscription.cancel().timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('cancel() did not complete'),
      );

      final atCancel = reads;
      local.emitChange();
      await settle();

      expect(reads, atCancel, reason: 'no reads after cancelling');
    });
  });
}

class _FakeLocalDataSource implements CategoryLocalDataSource {
  final _changes = StreamController<void>.broadcast();

  AppException? failWith;
  int nextId = 1;
  int? deletedId;
  int usage = 0;
  int children = 0;
  CategoryModel? found;
  CategoryType? lastType;
  List<CategoryModel> rows = [];
  final List<CategoryModel> added = [];
  void Function()? onList;

  void emitChange() => _changes.add(null);

  void _maybeThrow() {
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<int> add(CategoryModel category) async {
    _maybeThrow();
    added.add(category);
    return nextId;
  }

  @override
  Future<void> update(CategoryModel category) async => _maybeThrow();

  @override
  Future<void> delete(int id) async {
    _maybeThrow();
    deletedId = id;
  }

  @override
  Future<CategoryModel?> find(int id) async {
    _maybeThrow();
    return found;
  }

  @override
  Future<int> usageCount(int id) async {
    _maybeThrow();
    return usage;
  }

  @override
  Future<int> childCount(int id) async {
    _maybeThrow();
    return children;
  }

  @override
  Future<List<CategoryModel>> list({CategoryType? type}) async {
    lastType = type;
    onList?.call();
    _maybeThrow();
    return rows;
  }

  @override
  Future<void> dispose() => _changes.close();
}
