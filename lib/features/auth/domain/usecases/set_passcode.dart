import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/passcode_format.dart';
import '../repositories/auth_repository.dart';

/// Turns the passcode on. FR-SET-005.
///
/// Only when there is none: replacing a passcode is `ChangePasscode`, which
/// asks for the current one first. Without that split, anyone holding an
/// unlocked phone could set a PIN of their own from the settings screen and
/// lock the owner out of their own ledger.
class SetPasscode implements UseCase<Unit, String> {
  /// Creates the use case.
  const SetPasscode(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String params) async {
    if (PasscodeFormat.validate(params) case final failure?) {
      return Left(failure);
    }
    final existing = await _repository.hasPasscode();
    return existing.fold(Left.new, (has) {
      if (has) {
        return const Left(
          ValidationFailure(
            'A passcode is already set. Change it instead.',
            field: 'pin',
          ),
        );
      }
      return _repository.setPasscode(params);
    });
  }
}
