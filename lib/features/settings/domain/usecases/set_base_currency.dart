import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

/// Chooses the currency totals are expressed in. FR-SET-003, FR-ACC-005.
///
/// The same read-copy-save shape as `SetTheme`, with one rule of its own: a
/// currency code is three letters. Changing the base does not touch any
/// stored rate — rates are keyed by pair (E-34) — so the consequence of a
/// change is that rates *to the new base* may not exist yet, and accounts
/// without one fall back to being shown in their own currency and left out
/// of the total, as E-25 always had them.
class SetBaseCurrency implements UseCase<Unit, String> {
  /// Creates the use case.
  const SetBaseCurrency(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String params) async {
    final code = params.trim().toUpperCase();
    final failure = validate(code);
    if (failure != null) return Left(failure);

    final current = await _repository.get();
    return current.fold(
      Left.new,
      (settings) => _repository.save(settings.copyWith(currency: code)),
    );
  }

  /// Returns the reason [code] is invalid, or null if it is fine.
  static ValidationFailure? validate(String code) {
    final trimmed = code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(trimmed)) {
      return const ValidationFailure(
        'Enter a three-letter currency code, like LKR.',
        field: 'currency',
      );
    }
    return null;
  }
}
