import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/receipt_repository.dart';

/// The receipt photo at a path, as bytes a screen can draw. FR-RCP-012.
///
/// A kept photo is encrypted on disk (FR-RCP-012, NFR-SEC-002), so a
/// screen can no longer hand the path to an image widget; it asks here,
/// and the repository decrypts. A path the vault did not write — the
/// picker's file, on the review screen before Confirm — comes back as it
/// is, so one widget draws both. Null is a file that is gone, which the
/// history shows as a placeholder rather than a failure: the record is
/// what is kept, and it is still there.
///
/// The only rule of its own is that a blank path is refused before the
/// disk is asked, the same rule [ScanReceipt] applies.
class LoadReceiptImage implements UseCase<Uint8List?, String> {
  /// Creates the use case over [repository].
  const LoadReceiptImage(this._repository);

  final ReceiptRepository _repository;

  @override
  Future<Either<Failure, Uint8List?>> call(String params) async {
    if (params.trim().isEmpty) {
      return const Left(
        ValidationFailure('The receipt has no photo.', field: 'imagePath'),
      );
    }
    return _repository.loadImage(params);
  }
}
