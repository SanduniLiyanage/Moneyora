import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

/// Sets the share of income a suggested plan sets aside. FR-SET-008.
///
/// Whole percents, 0–100 — the bounds `AllocateBudget` already refuses
/// outside of, and the column's own `CHECK`. The Money Plan wizard starts
/// its savings field from this, so the target is typed once rather than on
/// every plan; 0, the column's default, leaves the wizard's suggestion.
class SetSavingsTarget implements UseCase<Unit, int> {
  /// Creates the use case.
  const SetSavingsTarget(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(int params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    final current = await _repository.get();
    return current.fold(
      Left.new,
      (settings) => _repository.save(
        settings.copyWith(savingsTargetPct: params.toDouble()),
      ),
    );
  }

  /// Returns the reason [percent] is refused, or null if it is fine.
  static ValidationFailure? validate(int percent) {
    if (percent < 0 || percent > 100) {
      return const ValidationFailure(
        'Choose a percentage from 0 to 100.',
        field: 'savingsTargetPct',
      );
    }
    return null;
  }
}
