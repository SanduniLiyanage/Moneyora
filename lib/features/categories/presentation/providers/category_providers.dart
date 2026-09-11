/// Presentation state for the categories feature.
///
/// These talk to **use cases**, never to a repository or a datasource, which
/// is the rule `scripts/check_architecture.sh` enforces and the reason a
/// screen can be tested by overriding one provider.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../injection.dart';
import '../../domain/entities/category.dart';

/// The categories, kept live. Both kinds unless [type] narrows it.
///
/// A `StreamProvider` rather than a future so a category created mid-entry
/// (E-13) appears on every picker without being told to refresh, the same
/// reasoning `accountsProvider` uses.
final categoriesProvider = StreamProvider.family<List<Category>, CategoryType?>(
  (ref, type) {
    return Stream.fromFuture(ref.watch(watchCategoriesProvider.future))
        .asyncExpand((watchCategories) => watchCategories(type))
        // A `Left` goes down the error channel so it arrives as
        // `AsyncValue.error` and each screen handles it in the branch its
        // `switch` already has - the same shape as `accountsProvider`.
        .transform(
          StreamTransformer<
            Either<Failure, List<Category>>,
            List<Category>
          >.fromHandlers(
            handleData: (result, sink) => result.match(sink.addError, sink.add),
          ),
        );
  },
);

/// Saves a category, exposing the attempt as an [AsyncValue].
///
/// An `AsyncNotifier` rather than local widget state, the same shape as
/// `SaveAccountController` and for the same reason: a save is in flight,
/// failed or done, and `AsyncValue` has no "success only" shape to forget.
class SaveCategoryController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates [category], or updates it when it already has an id.
  ///
  /// Returns true when it was written, so the caller can pop. The failure is
  /// left in [state] for the form to show, including the validation ones,
  /// which come from `AddCategory.validate` rather than being restated here.
  Future<bool> save(Category category) async {
    state = const AsyncValue<void>.loading();

    final Either<Failure, void> result;
    if (category.id == null) {
      final addCategory = await ref.read(addCategoryProvider.future);
      result = await addCategory(category);
    } else {
      final updateCategory = await ref.read(updateCategoryProvider.future);
      result = await updateCategory(category);
    }

    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        return true;
      },
    );
  }
}

/// Controller for the category form's save button.
final saveCategoryControllerProvider =
    AutoDisposeAsyncNotifierProvider<SaveCategoryController, void>(
      SaveCategoryController.new,
    );

/// Deleting a category. FR-EXP-004.
///
/// Separate from [SaveCategoryController] for the same reason
/// `AccountActionsController` is separate from `SaveAccountController`: this
/// is a single decision with its own refusal, from `DeleteCategory`, shown
/// rather than swallowed.
class DeleteCategoryController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Permanently removes [categoryId].
  ///
  /// Returns the failure rather than true/false, because the caller needs the
  /// sentence to show and not merely the fact that something went wrong.
  Future<Failure?> call(int categoryId) async {
    state = const AsyncValue<void>.loading();
    final deleteCategory = await ref.read(deleteCategoryProvider.future);
    final result = await deleteCategory(categoryId);

    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return failure;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        return null;
      },
    );
  }
}

/// Controller for the delete action.
final deleteCategoryControllerProvider =
    AutoDisposeAsyncNotifierProvider<DeleteCategoryController, void>(
      DeleteCategoryController.new,
    );
