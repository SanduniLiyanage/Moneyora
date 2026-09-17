import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

/// Chooses the day a month starts on. FR-SET-004.
///
/// 1–28, so that every month has the day — the 29th, 30th and 31st do not
/// exist in every month, and a period that started on a day February lacks
/// would need a rule nobody would guess. The schema's CHECK is the last
/// line; this produces a sentence.
class SetFirstDayOfMonth implements UseCase<Unit, int> {
  /// Creates the use case.
  const SetFirstDayOfMonth(this._repository);

  final SettingsRepository _repository;

  /// The first day the SRS allows.
  static const int minDay = 1;

  /// The last day the SRS allows: the last one every month has.
  static const int maxDay = 28;

  @override
  Future<Either<Failure, Unit>> call(int params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    final current = await _repository.get();
    return current.fold(
      Left.new,
      (settings) =>
          _repository.save(settings.copyWith(firstDayOfMonth: params)),
    );
  }

  /// Returns the reason [day] is refused, or null if it is fine.
  static ValidationFailure? validate(int day) {
    if (day < minDay || day > maxDay) {
      return const ValidationFailure(
        'Choose a day from 1 to 28, so every month has it.',
        field: 'firstDayOfMonth',
      );
    }
    return null;
  }
}
