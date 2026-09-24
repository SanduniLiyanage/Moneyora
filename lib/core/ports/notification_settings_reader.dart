import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';
import 'notification_settings.dart';

export 'notification_settings.dart';

/// Reads [NotificationSettings], from outside `features/settings/`.
/// FR-SET-007.
///
/// The same shape as [CalendarSettingsReader]: the settings feature's data
/// layer fulfils it, `injection.dart` hands it out, and the Money Plan's
/// budget alerts read through it without importing the feature that owns
/// the row.
abstract interface class NotificationSettingsReader {
  /// The settings, kept live: alerts turned on start at the next spend,
  /// without a restart.
  Stream<Either<Failure, NotificationSettings>> watch();
}
