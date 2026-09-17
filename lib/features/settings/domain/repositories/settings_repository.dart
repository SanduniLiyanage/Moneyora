import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/user_settings.dart';

/// What the settings feature needs from persistence. SRS §3.8.
///
/// One row, read whole and written whole: a preference is never changed on
/// its own in the database, so a use case reads, copies and saves. The
/// alternative — a method per column — is a repository that grows a method
/// for every setting the SRS names, which is the shape this file exists to
/// avoid.
abstract interface class SettingsRepository {
  /// The settings as stored.
  Future<Either<Failure, UserSettings>> get();

  /// Writes [settings] over the stored row.
  Future<Either<Failure, Unit>> save(UserSettings settings);

  /// The settings, kept live, so a theme chosen on the settings screen is
  /// drawn by the screen beneath it without either knowing about the other.
  Stream<Either<Failure, UserSettings>> watch();
}
