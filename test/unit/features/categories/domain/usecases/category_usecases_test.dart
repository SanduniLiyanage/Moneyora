import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/categories/domain/entities/category.dart';
import 'package:moneyora/features/categories/domain/repositories/category_repository.dart';
import 'package:moneyora/features/categories/domain/usecases/add_category.dart';
import 'package:moneyora/features/categories/domain/usecases/delete_category.dart';
import 'package:moneyora/features/categories/domain/usecases/update_category.dart';
import 'package:moneyora/features/categories/domain/usecases/watch_categories.dart';

/// The four category use cases share one collaborator, and the fake below is
/// most of the code either way — the same reasoning as
/// `account_usecases_test.dart`.
void main() {
  late _FakeRepository repository;

  Category category({
    int? id = 1,
    String name = 'Food',
    String colorHex = '#FF9800',
    CategoryType type = CategoryType.expense,
    int? parentId,
  }) => Category(
    id: id,
    name: name,
    icon: 'basket',
    colorHex: colorHex,
    type: type,
    parentId: parentId,
  );

  setUp(() => repository = _FakeRepository());

  group('AddCategory', () {
    test('saves a valid top-level category', () async {
      final result = await AddCategory(repository)(category(id: null));

      expect(result, const Right<Failure, int>(9));
      expect(repository.added?.name, 'Food');
    });

    test('rejects a blank name, naming the field', () async {
      expect(AddCategory.validate(category(name: '   '))?.field, 'name');
      expect(repository.added, isNull);
    });

    test('rejects a name too long for the list to render', () async {
      expect(AddCategory.validate(category(name: 'x' * 41)), isNotNull);
      expect(AddCategory.validate(category(name: 'x' * 40)), isNull);
    });

    test('rejects a colour that is not #RRGGBB', () async {
      expect(
        AddCategory.validate(category(colorHex: 'orange'))?.field,
        'colorHex',
      );
      expect(
        AddCategory.validate(category(colorHex: '#FFF'))?.field,
        'colorHex',
      );
    });

    test('rejects a category that names itself as its own parent', () async {
      final self = category(id: 5, parentId: 5);

      expect(AddCategory.validate(self)?.field, 'parentId');
    });

    test('refuses a parent that does not exist', () async {
      repository.found = null;

      final result = await AddCategory(repository)(
        category(id: null, parentId: 99),
      );

      expect(result.isLeft(), isTrue);
      expect(repository.added, isNull);
    });

    test('refuses a parent that is itself a sub-category', () async {
      // FR-EXP-005's two-level cap: a child of a child is one level too deep.
      repository.found = category(id: 2, parentId: 1);

      final result = await AddCategory(repository)(
        category(id: null, parentId: 2),
      );

      result.match(
        (failure) => expect((failure as ValidationFailure).field, 'parentId'),
        (_) => fail('should have refused'),
      );
    });

    test('refuses a parent of the wrong type', () async {
      repository.found = category(id: 2, type: CategoryType.income);

      final result = await AddCategory(repository)(
        category(id: null, type: CategoryType.expense, parentId: 2),
      );

      expect(result.isLeft(), isTrue);
    });

    test('accepts a top-level parent of the same type', () async {
      repository.found = category(id: 2, type: CategoryType.expense);

      final result = await AddCategory(repository)(
        category(id: null, type: CategoryType.expense, parentId: 2),
      );

      expect(result, const Right<Failure, int>(9));
      expect(repository.added?.parentId, 2);
    });
  });

  group('UpdateCategory', () {
    test('saves an edit', () async {
      final result = await UpdateCategory(repository)(
        category(name: 'Groceries'),
      );

      expect(result, const Right<Failure, Unit>(unit));
      expect(repository.updated?.name, 'Groceries');
    });

    test('refuses a category that was never saved', () async {
      final result = await UpdateCategory(repository)(category(id: null));

      expect(result.isLeft(), isTrue);
      expect(repository.updated, isNull);
    });

    test('applies the same rules as AddCategory', () async {
      final result = await UpdateCategory(repository)(category(name: ''));

      expect(result.isLeft(), isTrue);
    });

    test('refuses to re-parent under an invalid parent', () async {
      repository.found = null;

      final result = await UpdateCategory(repository)(
        category(id: 1, parentId: 99),
      );

      expect(result.isLeft(), isTrue);
      expect(repository.updated, isNull);
    });

    test('refuses to re-parent a category that has its own children', () async {
      // Otherwise a grandchild ends up one level past FR-EXP-005's cap.
      repository.found = category(id: 2, type: CategoryType.expense);
      repository.childCounts[1] = 3;

      final result = await UpdateCategory(repository)(
        category(id: 1, parentId: 2),
      );

      result.match(
        (failure) => expect(failure.message, contains('sub-categories')),
        (_) => fail('should have refused'),
      );
      expect(repository.updated, isNull);
    });

    test(
      'allows re-parenting a childless category under a valid parent',
      () async {
        repository.found = category(id: 2, type: CategoryType.expense);
        repository.childCounts[1] = 0;

        final result = await UpdateCategory(repository)(
          category(id: 1, parentId: 2),
        );

        expect(result, const Right<Failure, Unit>(unit));
        expect(repository.updated?.parentId, 2);
      },
    );
  });

  group('DeleteCategory', () {
    test('deletes a category nothing references', () async {
      final result = await DeleteCategory(repository)(1);

      expect(result, const Right<Failure, Unit>(unit));
      expect(repository.deletedId, 1);
    });

    test('refuses once it has a sub-category, and says how many', () async {
      repository.childCounts[1] = 2;

      final result = await DeleteCategory(repository)(1);

      expect(repository.deletedId, isNull);
      result.match(
        (failure) => expect(failure.message, contains('2 sub-categories')),
        (_) => fail('should have refused'),
      );
    });

    test('gets the singular right for one sub-category', () async {
      repository.childCounts[1] = 1;

      final result = await DeleteCategory(repository)(1);

      result.match(
        (failure) => expect(failure.message, contains('one sub-category')),
        (_) => fail('should have refused'),
      );
    });

    test(
      'refuses once it is used by a transaction, and says how many',
      () async {
        repository.usageCounts[1] = 12;

        final result = await DeleteCategory(repository)(1);

        expect(repository.deletedId, isNull);
        result.match(
          (failure) => expect(failure.message, contains('12 transactions')),
          (_) => fail('should have refused'),
        );
      },
    );

    test('checks children before usage', () async {
      // Both are wrong for different reasons; the message should name the
      // one that is actually true first rather than a coin flip.
      repository.childCounts[1] = 1;
      repository.usageCounts[1] = 1;

      final result = await DeleteCategory(repository)(1);

      result.match(
        (failure) => expect(failure.message, contains('sub-category')),
        (_) => fail('should have refused'),
      );
    });
  });

  group('WatchCategories', () {
    test('passes the type filter through', () async {
      await WatchCategories(repository)(CategoryType.income).first;

      expect(repository.watchedType, CategoryType.income);
    });

    test('forwards what the repository emits', () async {
      repository.categories = [category()];

      final emitted = await WatchCategories(repository)(null).first;

      expect(emitted.getOrElse((_) => []), hasLength(1));
    });
  });
}

class _FakeRepository implements CategoryRepository {
  List<Category> categories = [];
  Category? added;
  Category? updated;
  int? deletedId;
  Category? found;
  final Map<int, int> usageCounts = {};
  final Map<int, int> childCounts = {};
  CategoryType? watchedType;
  Failure? failWith;

  @override
  Future<Either<Failure, int>> add(Category category) async {
    if (failWith case final failure?) return Left(failure);
    added = category;
    return const Right(9);
  }

  @override
  Future<Either<Failure, Unit>> update(Category category) async {
    if (failWith case final failure?) return Left(failure);
    updated = category;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    if (failWith case final failure?) return Left(failure);
    deletedId = id;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Category?>> find(int id) async {
    if (failWith case final failure?) return Left(failure);
    return Right(found);
  }

  @override
  Future<Either<Failure, int>> usageCount(int id) async {
    if (failWith case final failure?) return Left(failure);
    return Right(usageCounts[id] ?? 0);
  }

  @override
  Future<Either<Failure, int>> childCount(int id) async {
    if (failWith case final failure?) return Left(failure);
    return Right(childCounts[id] ?? 0);
  }

  @override
  Future<Either<Failure, List<Category>>> list({CategoryType? type}) async {
    if (failWith case final failure?) return Left(failure);
    return Right(
      type == null
          ? categories
          : categories.where((c) => c.type == type).toList(),
    );
  }

  @override
  Stream<Either<Failure, List<Category>>> watch({CategoryType? type}) {
    watchedType = type;
    return Stream.value(Right(categories));
  }
}
