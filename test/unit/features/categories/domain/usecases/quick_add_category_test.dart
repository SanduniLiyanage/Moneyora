import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/theme/category_palette.dart';
import 'package:moneyora/core/widgets/category_icons.dart';
import 'package:moneyora/features/categories/domain/entities/category.dart';
import 'package:moneyora/features/categories/domain/repositories/category_repository.dart';
import 'package:moneyora/features/categories/domain/usecases/add_category.dart';
import 'package:moneyora/features/categories/domain/usecases/quick_add_category.dart';

void main() {
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());

  test(
    'the literal defaults match core/widgets and core/theme, not by luck',
    () {
      // domain/ cannot import either catalogue (rule 1: no Flutter), so
      // QuickAddCategory carries its own copy of their defaults. This is the
      // guard against the two silently drifting apart.
      expect(QuickAddCategory.defaultIcon, defaultCategoryIconKey);
      expect(QuickAddCategory.defaultColorHex, defaultCategoryColorHex);
    },
  );

  test(
    'creates a top-level category with the default icon and colour',
    () async {
      final result = await QuickAddCategory(AddCategory(repository))(
        name: 'Streaming',
        isExpense: true,
      );

      expect(result, const Right<Failure, int>(9));
      expect(repository.added?.name, 'Streaming');
      expect(repository.added?.type, CategoryType.expense);
      expect(repository.added?.parentId, isNull);
      expect(repository.added?.icon, defaultCategoryIconKey);
      expect(repository.added?.colorHex, defaultCategoryColorHex);
    },
  );

  test('creates an income category when told to', () async {
    await QuickAddCategory(AddCategory(repository))(
      name: 'Bonus',
      isExpense: false,
    );

    expect(repository.added?.type, CategoryType.income);
  });

  test('runs the same validation AddCategory does', () async {
    // Not a second set of rules — AddCategory.validate is what this refuses
    // on, so a blank name is caught exactly as it would be from the
    // categories screen's own form.
    final result = await QuickAddCategory(AddCategory(repository))(
      name: '   ',
      isExpense: true,
    );

    expect(result.isLeft(), isTrue);
    expect(repository.added, isNull);
  });
}

class _FakeRepository implements CategoryRepository {
  Category? added;

  @override
  Future<Either<Failure, int>> add(Category category) async {
    added = category;
    return const Right(9);
  }

  @override
  Future<Either<Failure, Unit>> update(Category category) async =>
      const Right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => const Right(unit);

  @override
  Future<Either<Failure, Category?>> find(int id) async => const Right(null);

  @override
  Future<Either<Failure, int>> usageCount(int id) async => const Right(0);

  @override
  Future<Either<Failure, int>> childCount(int id) async => const Right(0);

  @override
  Future<Either<Failure, List<Category>>> list({CategoryType? type}) async =>
      const Right([]);

  @override
  Stream<Either<Failure, List<Category>>> watch({CategoryType? type}) =>
      Stream.value(const Right([]));
}
