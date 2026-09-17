import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';
import 'calendar_settings.dart';

export 'calendar_settings.dart';

/// Reads [CalendarSettings], from outside `features/settings/`. FR-SET-004,
/// FR-SET-012.
///
/// The same shape as [ConversionReader] and [AccountReader] (E-27): the
/// settings feature's data layer fulfils it, `injection.dart` hands it out,
/// and analytics and the Money Plan read through it without importing the
/// feature that owns the row.
abstract interface class CalendarSettingsReader {
  /// The settings, kept live: a changed first weekday re-cuts every period
  /// on screen without a restart.
  Stream<Either<Failure, CalendarSettings>> watch();
}
