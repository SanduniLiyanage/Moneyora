import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/user_settings.dart';
import '../repositories/settings_repository.dart';

/// Chooses light, dark or the device's theme. FR-SET-001.
///
/// Reads the row, changes one field, writes the row back — the pattern every
/// later setting follows, so the repository stays at three methods however
/// many preferences the SRS names. There is nothing to validate: an enum
/// cannot hold a value the `users.theme` CHECK would refuse.
class SetTheme implements UseCase<Unit, AppThemeMode> {
  /// Creates the use case.
  const SetTheme(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(AppThemeMode params) async {
    final current = await _repository.get();
    return current.fold(
      Left.new,
      (settings) => _repository.save(settings.copyWith(theme: params)),
    );
  }
}
