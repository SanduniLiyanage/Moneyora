import 'package:equatable/equatable.dart';

/// The whole calendar months a plan's statistics look back over. FR-PLN-003.
///
/// Whole months, because the statistics are over *monthly totals* — a partial
/// month would read as a quiet one and drag every mean down — and because
/// FR-PLN-003 lets the user set the length in months, not days.
class LookbackWindow extends Equatable {
  /// Creates a window of [months] months ending with the month [lastMonth]
  /// falls in. Any day and time on [lastMonth] is ignored.
  const LookbackWindow({required this.months, required this.lastMonth});

  /// The [months] whole months before the one [date] falls in — what a plan
  /// generated mid-month looks back over, since the current month is not yet
  /// a data point.
  factory LookbackWindow.before(DateTime date, {int months = defaultMonths}) =>
      LookbackWindow(
        months: months,
        lastMonth: DateTime(date.year, date.month - 1),
      );

  /// FR-PLN-003's default.
  static const int defaultMonths = 6;

  /// The shortest window FR-PLN-003 allows.
  static const int minMonths = 1;

  /// The longest window FR-PLN-003 allows — and the one E-07 needs before
  /// seasonal detection is honest.
  static const int maxMonths = 24;

  /// How many months the window spans.
  final int months;

  /// Any date in the last month of the window.
  final DateTime lastMonth;

  /// True when [months] is inside FR-PLN-003's 1–24.
  bool get isValid => months >= minMonths && months <= maxMonths;

  /// The first day of the first month.
  DateTime get from => DateTime(lastMonth.year, lastMonth.month - months + 1);

  /// The last day of the last month.
  DateTime get to => DateTime(lastMonth.year, lastMonth.month + 1, 0);

  /// The first day of every month in the window, oldest first.
  List<DateTime> get monthStarts => [
    for (var i = 0; i < months; i++) DateTime(from.year, from.month + i),
  ];

  /// Where the month [date] falls in sits in [monthStarts], or -1 when it is
  /// outside the window.
  int indexOf(DateTime date) {
    final index = (date.year - from.year) * 12 + date.month - from.month;
    return index >= 0 && index < months ? index : -1;
  }

  @override
  List<Object?> get props => [
    months,
    DateTime(lastMonth.year, lastMonth.month),
  ];
}
