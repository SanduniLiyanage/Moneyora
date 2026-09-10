import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/category.dart';
import '../repositories/category_repository.dart';
import 'add_category.dart';

/// Renames, recolours, re-icons or re-parents an existing category.
/// FR-EXP-004, FR-EXP-005.
class UpdateCategory implements UseCase<Unit, Category> {
  /// Creates the use case.
  const UpdateCategory(this._repository);

  final CategoryRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(Category params) async {
    final id = params.id;
    if (id == null) {
      return const Left(ValidationFailure('This category was never saved.'));
    }

    // Delegated, not restated - an edit form accepting what a create form
    // rejects is a bug nobody thinks to look for.
    final failure = AddCategory.validate(params);
    if (failure != null) return Left(failure);

    final parentId = params.parentId;
    if (parentId == null) return _repository.update(params);

    final found = await _repository.find(parentId);
    return found.match(Left.new, (parent) async {
      final hierarchyFailure = AddCategory.validateParent(parent, params);
      if (hierarchyFailure != null) return Left(hierarchyFailure);

      // A category with children of its own cannot become a child - that
      // would put a grandchild under it, past FR-EXP-005's two-level cap.
      final children = await _repository.childCount(id);
      return children.match(Left.new, (count) async {
        if (count > 0) {
          return const Left(
            ValidationFailure(
              'This category has sub-categories of its own, so it cannot '
              'become a sub-category - move or delete them first.',
              field: 'parentId',
            ),
          );
        }
        return _repository.update(params);
      });
    });
  }
}
