import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/category.dart';
import '../repositories/category_repository.dart';

/// Watches the category list. FR-EXP-004, FR-EXP-011.
///
/// A stream, not a one-shot read, so a category created mid-entry (E-13)
/// appears on the entry screen's own picker without it being told to refresh.
class WatchCategories implements StreamUseCase<List<Category>, CategoryType?> {
  /// Creates the use case.
  const WatchCategories(this._repository);

  final CategoryRepository _repository;

  /// [params] narrows to one kind, or null for both.
  @override
  Stream<Either<Failure, List<Category>>> call(CategoryType? params) =>
      _repository.watch(type: params);
}
