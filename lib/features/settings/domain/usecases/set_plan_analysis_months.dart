import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

/// Chooses how many months of history the Money Plan learns from.
/// FR-SET-012, FR-PLN-003.
///
/// 1–24. The Money Plan's `LookbackWindow` carries the same bounds as
/// `minMonths` / `maxMonths`, and E-07 is why 24 exists: seasonal detection
/// over six points is noise. This is the only place the number is set; the
/// wizard reads it and says where to change it.
class SetPlanAnalysisMonths implements UseCase<Unit, int> {
  /// Creates the use case.
  const SetPlanAnalysisMonths(this._repository);

  final SettingsRepository _repository;

  /// The shortest window FR-PLN-003 allows.
  static const int minMonths = 1;

  /// The longest window FR-PLN-003 allows.
  static const int maxMonths = 24;

  @override
  Future<Either<Failure, Unit>> call(int params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    final current = await _repository.get();
    return current.fold(
      Left.new,
      (settings) =>
          _repository.save(settings.copyWith(planAnalysisMonths: params)),
    );
  }

  /// Returns the reason [months] is refused, or null if it is fine.
  static ValidationFailure? validate(int months) {
    if (months < minMonths || months > maxMonths) {
      return const ValidationFailure(
        'Choose between 1 and 24 months.',
        field: 'planAnalysisMonths',
      );
    }
    return null;
  }
}
