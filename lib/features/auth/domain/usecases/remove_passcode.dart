import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/pin_verdict.dart';
import '../repositories/auth_repository.dart';
import 'verify_passcode.dart';

/// Turns the passcode off, on proof of the current one. FR-SET-005.
///
/// Proof goes through [VerifyPasscode] for the reason `ChangePasscode` gives:
/// a wrong PIN typed here costs what it costs on the lock screen. Takes the
/// current PIN as its parameter; [PinAccepted] means the passcode is gone.
class RemovePasscode implements UseCase<PinVerdict, String> {
  /// Creates the use case over the same gate the lock screen uses.
  const RemovePasscode(this._repository, this._verify);

  final AuthRepository _repository;
  final VerifyPasscode _verify;

  @override
  Future<Either<Failure, PinVerdict>> call(String params) async {
    final existing = await _repository.hasPasscode();
    return existing.fold(Left.new, (has) async {
      if (!has) {
        return const Left(ValidationFailure('No passcode is set.'));
      }
      final verdict = await _verify(params);
      return verdict.fold(Left.new, (verdict) async {
        if (verdict is! PinAccepted) return Right(verdict);
        final cleared = await _repository.clearPasscode();
        return cleared.map((_) => verdict);
      });
    });
  }
}
