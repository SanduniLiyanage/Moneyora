import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/category_repository.dart';

/// Permanently removes a category that nothing depends on. FR-EXP-004.
///
/// Refuses once a transaction cites it or a sub-category is parented under
/// it, and says which. `DeleteAccount`'s precedent (FR-ACC-007, E-25): the
/// use case decides and returns its own refusal rather than orphaning a
/// transaction's category or a child's parent.
class DeleteCategory implements UseCase<Unit, int> {
  /// Creates the use case.
  const DeleteCategory(this._repository);

  final CategoryRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(int params) async {
    final children = await _repository.childCount(params);
    return children.match(Left.new, (childCount) async {
      if (childCount > 0) {
        return Left(
          ValidationFailure(
            childCount == 1
                ? 'This category has one sub-category. Delete or move it '
                      'first.'
                : 'This category has $childCount sub-categories. Delete or '
                      'move them first.',
          ),
        );
      }

      final used = await _repository.usageCount(params);
      return used.match(Left.new, (usageCount) async {
        if (usageCount > 0) {
          return Left(
            ValidationFailure(
              usageCount == 1
                  ? 'This category is used by one transaction and cannot be '
                        'deleted.'
                  : 'This category is used by $usageCount transactions and '
                        'cannot be deleted.',
            ),
          );
        }
        return _repository.delete(params);
      });
    });
  }
}
