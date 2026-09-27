import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/expense_photos.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/transaction.dart';

/// What changed about a row's photo, once the change is final.
class PhotoCleanup extends Equatable {
  /// Creates the parameters.
  const PhotoCleanup({this.before, this.after, this.keptHere = const {}});

  /// The row as it was, or null for a new one.
  final Transaction? before;

  /// The row as written, or null when it was deleted or never saved.
  final Transaction? after;

  /// Photos kept while the form was open, whether or not one was used.
  final Set<String> keptHere;

  @override
  List<Object?> get props => [before, after, keptHere];
}

/// Deletes the kept photos no row names any more. FR-EXP-009.
///
/// A photo is sealed in the vault the moment it is chosen, so replacing
/// one, removing one, backing out of the form, or deleting the expense
/// each leave a file behind. Only a photo attached by hand is ever
/// discarded — [Transaction.attachedPhotoPath] — never a scan's.
///
/// Called after the write it follows has succeeded, so a failed save never
/// loses the photo it was going to keep.
class DiscardUnusedPhotos implements UseCase<Unit, PhotoCleanup> {
  /// Creates the use case.
  const DiscardUnusedPhotos(this._photos);

  final ExpensePhotos _photos;

  /// The paths [params] leaves unnamed. Pure, for the test.
  static Set<String> unused(PhotoCleanup params) {
    final owned = {...params.keptHere, ?params.before?.attachedPhotoPath};
    return owned.difference({?params.after?.receiptImagePath});
  }

  @override
  Future<Either<Failure, Unit>> call(PhotoCleanup params) async {
    // Every file is tried: one that will not go is no reason to keep the
    // rest. The first failure is what is reported.
    Failure? first;
    for (final path in unused(params)) {
      final result = await _photos.discard(path);
      first ??= result.getLeft().toNullable();
    }
    return first == null ? const Right(unit) : Left(first);
  }
}
