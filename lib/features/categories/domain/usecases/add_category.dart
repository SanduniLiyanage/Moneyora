import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/category.dart';
import '../repositories/category_repository.dart';

/// Creates a category. FR-EXP-004.
class AddCategory implements UseCase<int, Category> {
  /// Creates the use case.
  const AddCategory(this._repository);

  final CategoryRepository _repository;

  @override
  Future<Either<Failure, int>> call(Category params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    final parentId = params.parentId;
    if (parentId == null) return _repository.add(params);

    final found = await _repository.find(parentId);
    return found.match(Left.new, (parent) async {
      final hierarchyFailure = validateParent(parent, params);
      if (hierarchyFailure != null) return Left(hierarchyFailure);
      return _repository.add(params);
    });
  }

  /// Returns the reason [category] cannot be saved, or null if it can.
  ///
  /// Public and static so a form can check as the user types. Does not
  /// validate [Category.parentId] against the parent's own state - that
  /// needs a repository lookup and lives in [call] and [validateParent].
  static ValidationFailure? validate(Category category) {
    if (category.name.trim().isEmpty) {
      return const ValidationFailure(
        'Give the category a name.',
        field: 'name',
      );
    }

    if (category.name.trim().length > 40) {
      return const ValidationFailure(
        'That name is too long - 40 characters at most.',
        field: 'name',
      );
    }

    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(category.colorHex)) {
      return const ValidationFailure(
        'Pick a colour for the category.',
        field: 'colorHex',
      );
    }

    if (category.icon.trim().isEmpty) {
      return const ValidationFailure(
        'Pick an icon for the category.',
        field: 'icon',
      );
    }

    if (category.parentId != null && category.parentId == category.id) {
      return const ValidationFailure(
        'A category cannot be its own parent.',
        field: 'parentId',
      );
    }

    return null;
  }

  /// Returns the reason [parent] cannot be [child]'s parent, or null if it
  /// can. FR-EXP-005's two-level cap.
  static ValidationFailure? validateParent(Category? parent, Category child) {
    if (parent == null) {
      return const ValidationFailure(
        'That parent category no longer exists.',
        field: 'parentId',
      );
    }

    if (parent.isChild) {
      return const ValidationFailure(
        'Sub-categories can only be one level deep - pick a top-level '
        'category as the parent.',
        field: 'parentId',
      );
    }

    if (parent.type != child.type) {
      return ValidationFailure(
        child.type == CategoryType.expense
            ? 'Pick an expense category as the parent.'
            : 'Pick an income category as the parent.',
        field: 'parentId',
      );
    }

    return null;
  }
}
