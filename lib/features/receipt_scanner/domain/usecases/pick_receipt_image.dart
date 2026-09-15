import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/receipt_image_source.dart';
import '../repositories/receipt_repository.dart';

/// A receipt photo from the camera or the gallery, as a path. FR-RCP-002.
///
/// The first stage of the pipeline (SDD §7.2). `Right(null)` is the user
/// backing out of the picker, which is not a failure and gets no message;
/// a refused permission is the repository's [PermissionFailure], and the
/// screen shows its sentence.
///
/// Nothing here is the pipeline: [ReadReceiptImage] takes the path from
/// here, so a screen can offer both sources and run the same stages on
/// whichever the user picked.
class PickReceiptImage implements UseCase<String?, ReceiptImageSource> {
  /// Creates the use case over [repository].
  const PickReceiptImage(this._repository);

  final ReceiptRepository _repository;

  @override
  Future<Either<Failure, String?>> call(ReceiptImageSource params) =>
      _repository.pickImage(params);
}
