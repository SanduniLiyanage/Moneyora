import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

/// Chooses the day a week starts on. FR-SET-004.
///
/// [DateTime.sunday] or [DateTime.monday], which are the two the SRS names.
/// The column would accept any of the seven — the schema was written wider
/// than the requirement — but offering Wednesday-first weeks is not a
/// feature anyone asked for, and a use case that accepted it would be the
/// only place the app knew it could.
class SetFirstDayOfWeek implements UseCase<Unit, int> {
  /// Creates the use case.
  const SetFirstDayOfWeek(this._repository);

  final SettingsRepository _repository;

  /// The days the SRS allows a week to start on.
  static const List<int> allowed = [DateTime.monday, DateTime.sunday];

  @override
  Future<Either<Failure, Unit>> call(int params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    final current = await _repository.get();
    return current.fold(
      Left.new,
      (settings) => _repository.save(settings.copyWith(firstDayOfWeek: params)),
    );
  }

  /// Returns the reason [weekday] is refused, or null if it is fine.
  static ValidationFailure? validate(int weekday) {
    if (!allowed.contains(weekday)) {
      return const ValidationFailure(
        'A week starts on Sunday or Monday.',
        field: 'firstDayOfWeek',
      );
    }
    return null;
  }
}
