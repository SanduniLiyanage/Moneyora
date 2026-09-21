import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/passcode_format.dart';
import '../entities/pin_verdict.dart';
import '../repositories/auth_repository.dart';
import 'verify_passcode.dart';

/// The current PIN and the one to replace it with.
class ChangePasscodeParams extends Equatable {
  /// Creates the parameters.
  const ChangePasscodeParams({required this.current, required this.next});

  /// The passcode set today.
  final String current;

  /// The passcode wanted instead.
  final String next;

  @override
  List<Object?> get props => [current, next];
}

/// Replaces the passcode, on proof of the current one. FR-SET-005.
///
/// The proof goes through [VerifyPasscode], so a wrong current PIN here is
/// counted and locked out exactly as one on the lock screen is — this flow
/// is not a second set of five attempts. The verdict comes back as the
/// result: [PinAccepted] means the passcode was changed, and either other
/// verdict means it was not and says where the gate stands.
class ChangePasscode implements UseCase<PinVerdict, ChangePasscodeParams> {
  /// Creates the use case over the same gate the lock screen uses.
  const ChangePasscode(this._repository, this._verify);

  final AuthRepository _repository;
  final VerifyPasscode _verify;

  /// The refusal for the new PIN, or null when it is acceptable.
  ///
  /// Shown by the screen as the user types, so the sentence they see is the
  /// one this use case would refuse with.
  static ValidationFailure? validate(ChangePasscodeParams params) {
    if (PasscodeFormat.validate(params.next) case final failure?) {
      return failure;
    }
    if (params.next == params.current) {
      return const ValidationFailure(
        'Choose a PIN different from the current one.',
        field: 'pin',
      );
    }
    return null;
  }

  @override
  Future<Either<Failure, PinVerdict>> call(ChangePasscodeParams params) async {
    if (validate(params) case final failure?) return Left(failure);

    final existing = await _repository.hasPasscode();
    return existing.fold(Left.new, (has) async {
      if (!has) {
        return const Left(ValidationFailure('No passcode is set.'));
      }
      final verdict = await _verify(params.current);
      return verdict.fold(Left.new, (verdict) async {
        if (verdict is! PinAccepted) return Right(verdict);
        final stored = await _repository.setPasscode(params.next);
        return stored.map((_) => verdict);
      });
    });
  }
}
