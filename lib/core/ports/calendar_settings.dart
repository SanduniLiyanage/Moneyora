import 'package:equatable/equatable.dart';

/// How the user's calendar is cut: where a week starts, where a month
/// starts, and how far back the Money Plan looks. FR-SET-004, FR-SET-012.
///
/// Three settings from the `users` row, read by three features — analytics
/// cuts its periods with the first two, the Money Plan cuts its periods and
/// its lookback with all three — none of which may import the settings
/// feature (rule 4 of `check_architecture.sh`). So the value lives in
/// `core/ports/`, the way [ConversionTable] does, and [CalendarSettingsReader]
/// is the seam.
class CalendarSettings extends Equatable {
  /// Creates the settings.
  const CalendarSettings({
    this.firstWeekday = DateTime.sunday,
    this.firstDayOfMonth = 1,
    this.planAnalysisMonths = 6,
  });

  /// The schema's column defaults, which every seeded row starts with.
  ///
  /// Sunday, not Monday: the DBD (§3.1) and the seed say so. The code drew
  /// Monday-first weeks until FR-SET-004 read this row, so an install that
  /// never chose sees its week start a day earlier once it does — and can
  /// choose Monday under Settings.
  static const CalendarSettings defaults = CalendarSettings();

  /// A `DateTime` weekday constant: [DateTime.monday] (1) to
  /// [DateTime.sunday] (7). FR-SET-004 offers Sunday and Monday.
  final int firstWeekday;

  /// 1–28, so every month has it. FR-SET-004. A "month" period runs from
  /// this day to the day before it in the next month, which is what a month
  /// means to someone paid on the 25th.
  final int firstDayOfMonth;

  /// 1–24 whole months of history the Money Plan learns from. FR-SET-012,
  /// FR-PLN-003.
  final int planAnalysisMonths;

  @override
  List<Object?> get props => [
    firstWeekday,
    firstDayOfMonth,
    planAnalysisMonths,
  ];
}
