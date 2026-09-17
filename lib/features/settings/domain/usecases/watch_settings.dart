import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/user_settings.dart';
import '../repositories/settings_repository.dart';

/// The user's preferences, kept live. SRS §3.8.
///
/// What the app root reads for its theme (FR-SET-001) and what every later
/// setting's consumer reads too, so a change made on the settings screen
/// reaches whatever draws it without a restart.
class WatchSettings implements StreamUseCase<UserSettings, NoParams> {
  /// Creates the use case.
  const WatchSettings(this._repository);

  final SettingsRepository _repository;

  @override
  Stream<Either<Failure, UserSettings>> call(NoParams params) =>
      _repository.watch();
}
