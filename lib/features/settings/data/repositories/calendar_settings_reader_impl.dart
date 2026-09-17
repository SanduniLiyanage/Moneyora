/// The settings feature's answer to [CalendarSettingsReader]: three columns
/// of the `users` row, as the value other features read.
library;

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/calendar_settings_reader.dart';
import '../../domain/repositories/settings_repository.dart';

/// Fulfils [CalendarSettingsReader] over [SettingsRepository].
///
/// A projection, not a join: unlike `ConversionReaderImpl` there is one
/// stream beneath, so this is a `map` and nothing more.
class CalendarSettingsReaderImpl implements CalendarSettingsReader {
  /// Creates the reader.
  const CalendarSettingsReaderImpl(this._settings);

  final SettingsRepository _settings;

  @override
  Stream<Either<Failure, CalendarSettings>> watch() => _settings.watch().map(
    (result) => result.map(
      (s) => CalendarSettings(
        firstWeekday: s.firstDayOfWeek,
        firstDayOfMonth: s.firstDayOfMonth,
        planAnalysisMonths: s.planAnalysisMonths,
      ),
    ),
  );
}
