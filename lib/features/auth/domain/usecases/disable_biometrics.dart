import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/auth_repository.dart';

/// Turns biometric unlock off. NFR-SEC-004.
///
/// No prompt required: the PIN is still there either way, and asking for a
/// fingerprint to turn a fingerprint off protects nothing.
class DisableBiometrics implements UseCase<Unit, NoParams> {
  /// Creates the use case over [repository].
  const DisableBiometrics(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) =>
      _repository.setBiometricsEnabled(enabled: false);
}
