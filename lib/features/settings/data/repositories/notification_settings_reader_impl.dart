/// The settings feature's answer to [NotificationSettingsReader]: the
/// notification columns of the `users` row, as the value other features
/// read.
library;

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/notification_settings_reader.dart';
import '../../domain/repositories/settings_repository.dart';

/// Fulfils [NotificationSettingsReader] over [SettingsRepository].
/// FR-SET-007, FR-SET-006.
///
/// A projection, the shape `CalendarSettingsReaderImpl` has: one stream
/// beneath, so a `map` and nothing more.
class NotificationSettingsReaderImpl implements NotificationSettingsReader {
  /// Creates the reader.
  const NotificationSettingsReaderImpl(this._settings);

  final SettingsRepository _settings;

  @override
  Stream<Either<Failure, NotificationSettings>> watch() =>
      _settings.watch().map(
        (result) => result.map(
          (s) => NotificationSettings(
            budgetAlertsEnabled: s.budgetAlertsEnabled,
            recurringRemindersEnabled: s.recurringRemindersEnabled,
            reminderDaysBefore: s.reminderDaysBefore,
            reminderMinuteOfDay: s.reminderMinuteOfDay,
          ),
        ),
      );
}
