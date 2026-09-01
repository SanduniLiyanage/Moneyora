import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// Contract for every business operation in the app.
///
/// One class per operation, one public method. If a use case needs a second
/// public method, it is two use cases.
///
/// [T] is what the operation returns on success; [Params] is its input.
/// Use [NoParams] when there is no input.
///
/// Implementations live in `features/<feature>/domain/usecases/` and must stay
/// pure Dart — see `docs/ARCHITECTURE.md` §1.
abstract class UseCase<T, Params> {
  /// Runs the operation.
  ///
  /// Returns `Left(Failure)` on any error and `Right(T)` on success.
  /// Implementations must not throw; validate inputs and return a
  /// [ValidationFailure] instead.
  Future<Either<Failure, T>> call(Params params);
}

/// Contract for an operation that emits a continuous stream of results, such
/// as watching the active plan's progress.
abstract class StreamUseCase<T, Params> {
  Stream<Either<Failure, T>> call(Params params);
}

/// Input marker for use cases that take no arguments.
///
/// ```dart
/// final result = await getActivePlan(const NoParams());
/// ```
class NoParams {
  const NoParams();

  @override
  bool operator ==(Object other) => other is NoParams;

  @override
  int get hashCode => 0;
}
