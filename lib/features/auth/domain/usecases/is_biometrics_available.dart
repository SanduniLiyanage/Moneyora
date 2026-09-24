import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/biometric_gateway.dart';

/// Whether the device has a usable biometric sensor. NFR-SEC-004.
///
/// Read by the settings screen to decide whether to offer the toggle at
/// all — a phone with no sensor, or nothing enrolled, gets no row rather
/// than one that fails the moment it is touched.
class IsBiometricsAvailable implements UseCase<bool, NoParams> {
  /// Creates the use case over [gateway].
  const IsBiometricsAvailable(this._gateway);

  final BiometricGateway _gateway;

  @override
  Future<Either<Failure, bool>> call(NoParams params) => _gateway.isAvailable();
}
