import 'package:fpdart/fpdart.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/repositories/biometric_gateway.dart';

/// Over `local_auth`. NFR-SEC-004.
///
/// Never unit-tested — a method channel does not answer in a VM test, the
/// way ML Kit's does not (E-20's seam). Verified on the emulator with
/// `adb -e emu finger touch 1`; widget tests fake [BiometricGateway] itself.
class LocalAuthBiometricGateway implements BiometricGateway {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<Either<Failure, bool>> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return Right(canCheck && supported);
    } on Exception {
      // A probe, not a user action: an unreadable sensor just means no
      // toggle is offered, not a failure to show.
      return const Right(false);
    }
  }

  @override
  Future<Either<Failure, bool>> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // The OS never substitutes the device PIN/pattern for this prompt
        // — Moneyora's own PIN is the fallback, and offering two would blur
        // which one the lockout in `VerifyPasscode` is defending.
        biometricOnly: true,
      );
      return Right(ok);
    } on Exception {
      return const Left(
        PermissionFailure(
          'Could not use biometric authentication. Use your PIN instead.',
        ),
      );
    }
  }
}
