import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';

/// The device's biometric sensor — fingerprint or face. NFR-SEC-004.
///
/// A separate port from `AuthRepository`, which only ever knew the passcode
/// and its lockout: the sensor is a capability the OS exposes, not state
/// this app stores, so it does not belong on the same interface. Abstract
/// in domain because `EnableBiometrics` and `AuthenticateWithBiometrics`
/// need to authenticate as a step in their own logic, not merely read a
/// stored answer.
abstract class BiometricGateway {
  /// Whether the device has a usable sensor with something enrolled.
  Future<Either<Failure, bool>> isAvailable();

  /// Prompts for biometric authentication, showing [reason]. True on
  /// success; false when the user cancelled or failed the prompt — never a
  /// [Failure] for that, which is a refusal, not an error.
  Future<Either<Failure, bool>> authenticate(String reason);
}
