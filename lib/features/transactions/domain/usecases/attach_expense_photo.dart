import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/expense_photos.dart';
import '../../../../core/usecases/usecase.dart';

/// Takes or picks a photo for an expense and keeps it sealed. FR-EXP-009.
///
/// The kept path, or null when the user backed out. The photo is in the
/// vault from this moment, before the expense is saved, so a form that is
/// then abandoned has to hand it to `DiscardUnusedPhotos`; the entry screen
/// does.
class AttachExpensePhoto implements UseCase<String?, PhotoSource> {
  /// Creates the use case.
  const AttachExpensePhoto(this._photos);

  final ExpensePhotos _photos;

  @override
  Future<Either<Failure, String?>> call(PhotoSource params) =>
      _photos.pickAndKeep(params);
}
