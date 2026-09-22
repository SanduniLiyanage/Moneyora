import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/biometric_gateway.dart';

/// Prompts biometric authentication, for the lock screen. NFR-SEC-004.
///
/// Stays usable while a PIN lockout is running — the OS rate-limits the
/// sensor itself, and the lockout is a PIN brute-force defence, not a
/// biometric one. [params] is the reason shown on the OS prompt.
class AuthenticateWithBiometrics implements UseCase<bool, String> {
  /// Creates the use case over [gateway].
  const AuthenticateWithBiometrics(this._gateway);

  final BiometricGateway _gateway;

  @override
  Future<Either<Failure, bool>> call(String params) =>
      _gateway.authenticate(params);
}
