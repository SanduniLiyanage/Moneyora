import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/category.dart';

/// What the app can do with categories. FR-EXP-004, FR-EXP-005.
///
/// Declared here and implemented in `data/`, so the use cases above it depend
/// on this interface rather than on sqflite. Every method returns
/// `Either<Failure, T>` and none throws.
abstract interface class CategoryRepository {
  /// Saves a new category, returning its assigned id.
  Future<Either<Failure, int>> add(Category category);

  /// Updates an existing category.
  Future<Either<Failure, Unit>> update(Category category);

  /// Permanently removes a category.
  ///
  /// Only safe when nothing references it - see [usageCount] and
  /// [childCount]. The repository reports those counts rather than deciding
  /// what to do about them; that judgement belongs to a use case.
  Future<Either<Failure, Unit>> delete(int id);

  /// Reads one category, or null if [id] does not exist.
  ///
  /// Used to validate a parent before it is assigned to a child - see
  /// `AddCategory`.
  Future<Either<Failure, Category?>> find(int id);

  /// How many transactions or transaction-split rows cite [id] as their
  /// category.
  Future<Either<Failure, int>> usageCount(int id);

  /// How many categories cite [id] as their [Category.parentId].
  Future<Either<Failure, int>> childCount(int id);

  /// Reads categories, in seed/sort order. Both kinds unless [type] narrows
  /// it.
  Future<Either<Failure, List<Category>>> list({CategoryType? type});

  /// Watches categories, so a create, rename or delete on one screen is
  /// visible on every other without a manual refresh.
  Stream<Either<Failure, List<Category>>> watch({CategoryType? type});
}
