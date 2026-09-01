/// Failures are the domain layer's vocabulary for "something went wrong".
///
/// They are pure Dart values — comparable, printable, and safe to hand to the
/// presentation layer. Data-layer [AppException]s are translated into these at
/// the repository boundary; see `docs/ARCHITECTURE.md` §3.
library;

/// Base for every failure surfaced above the data layer.
sealed class Failure {
  const Failure(this.message);

  /// User-facing message. Keep it plain — this string can reach the UI.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() => '$runtimeType($message)';
}

/// A local database operation failed.
class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Could not read or write local data.']);
}

/// The encrypted database could not be unlocked.
class EncryptionFailure extends Failure {
  const EncryptionFailure([
    super.message = 'Could not unlock the secure database.',
  ]);
}

/// An optional remote call failed. Callers must degrade gracefully.
class ServerFailure extends Failure {
  const ServerFailure([super.message = 'The service is unavailable.']);
}

/// The device is offline. Expected and recoverable — never surface this as an
/// error for a core (offline-first) feature.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection.']);
}

/// Input violated a business rule. Thrown by use cases, not by repositories.
class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.field});

  /// Which input was rejected, so the UI can highlight the right control.
  final String? field;

  @override
  bool operator ==(Object other) =>
      other is ValidationFailure &&
      message == other.message &&
      field == other.field;

  @override
  int get hashCode => Object.hash(runtimeType, message, field);
}

/// OCR ran but produced nothing usable (FR-RCP-011 low-confidence path).
class OcrFailure extends Failure {
  const OcrFailure([
    super.message = 'Could not read this receipt. Try a clearer photo.',
  ]);
}

/// Not enough transaction history to generate a meaningful plan.
///
/// Expected for new users — SRS risk R6. The UI should offer a manual plan
/// rather than treating this as an error state.
class InsufficientDataFailure extends Failure {
  const InsufficientDataFailure({
    required this.monthsAvailable,
    required this.monthsRequired,
  }) : super('Not enough spending history to build a reliable plan yet.');

  final int monthsAvailable;
  final int monthsRequired;

  @override
  bool operator ==(Object other) =>
      other is InsufficientDataFailure &&
      monthsAvailable == other.monthsAvailable &&
      monthsRequired == other.monthsRequired;

  @override
  int get hashCode => Object.hash(runtimeType, monthsAvailable, monthsRequired);
}

/// A device permission was denied.
class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}
