import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/expense_photos.dart';
import '../../../../core/usecases/usecase.dart';

/// An expense's photo, decrypted for the screen. FR-EXP-009.
///
/// Null when the file is gone: the row keeps its path either way, and the
/// screen says the photo is missing rather than failing.
class LoadExpensePhoto implements UseCase<Uint8List?, String> {
  /// Creates the use case.
  const LoadExpensePhoto(this._photos);

  final ExpensePhotos _photos;

  @override
  Future<Either<Failure, Uint8List?>> call(String params) {
    if (params.trim().isEmpty) {
      return Future.value(const Right(null));
    }
    return _photos.read(params);
  }
}
