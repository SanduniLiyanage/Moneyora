import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/auth_repository.dart';
import '../repositories/biometric_gateway.dart';

/// Turns biometric unlock on, after one successful prompt. NFR-SEC-004.
///
/// Refused when no passcode is set: biometrics is a second way in, and the
/// PIN is what it falls back to when the sensor refuses. [params] is the
/// reason shown on the OS prompt. A declined or failed prompt is
/// `Right(false)` — the toggle simply does not move, which is not an error.
class EnableBiometrics implements UseCase<bool, String> {
  /// Creates the use case over [repository] and [gateway].
  const EnableBiometrics(this._repository, this._gateway);

  final AuthRepository _repository;
  final BiometricGateway _gateway;

  @override
  Future<Either<Failure, bool>> call(String params) async {
    final hasPasscode = await _repository.hasPasscode();
    return hasPasscode.fold(Left.new, (has) async {
      if (!has) {
        return const Left(
          ValidationFailure(
            'Set a passcode before turning on biometric unlock.',
          ),
        );
      }
      final authenticated = await _gateway.authenticate(params);
      return authenticated.fold(Left.new, (ok) async {
        if (!ok) return const Right(false);
        final saved = await _repository.setBiometricsEnabled(enabled: true);
        return saved.map((_) => true);
      });
    });
  }
}
