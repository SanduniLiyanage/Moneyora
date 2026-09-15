import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/recognised_text.dart';
import '../repositories/receipt_repository.dart';

/// The text off a receipt image, as lines. FR-RCP-004.
///
/// The third stage of the pipeline (SDD §7.2): after capture — and after
/// FR-RCP-003's preprocessing, once that lands — and before
/// [ParseReceiptText]. Nothing here knows ML Kit exists; the repository
/// does, which is what lets this run on the VM against a fake.
///
/// The only rule of its own is that an empty path is refused before the
/// recogniser is asked: the picker returning nothing is a cancelled pick,
/// not a receipt that could not be read, and the two deserve different
/// messages.
class ScanReceipt implements UseCase<RecognisedText, String> {
  /// Creates the use case over [repository].
  const ScanReceipt(this._repository);

  final ReceiptRepository _repository;

  @override
  Future<Either<Failure, RecognisedText>> call(String params) async {
    if (params.trim().isEmpty) {
      return const Left(
        ValidationFailure('No image was chosen.', field: 'imagePath'),
      );
    }
    return _repository.scanReceipt(params);
  }
}
