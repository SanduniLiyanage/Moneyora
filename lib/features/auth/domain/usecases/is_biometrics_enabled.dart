import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/auth_repository.dart';

/// Whether biometric unlock is turned on. NFR-SEC-004.
class IsBiometricsEnabled implements UseCase<bool, NoParams> {
  /// Creates the use case over [repository].
  const IsBiometricsEnabled(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, bool>> call(NoParams params) =>
      _repository.isBiometricsEnabled();
}
