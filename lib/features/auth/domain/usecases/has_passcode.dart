import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/auth_repository.dart';

/// Whether the app is behind a passcode. FR-SET-005.
///
/// Read once at launch to decide whether the lock screen is drawn at all,
/// and by the settings screen to say which of set, change and remove it
/// should offer.
class HasPasscode implements UseCase<bool, NoParams> {
  /// Creates the use case.
  const HasPasscode(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, bool>> call(NoParams params) =>
      _repository.hasPasscode();
}
