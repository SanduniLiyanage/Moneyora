import 'package:equatable/equatable.dart';

/// Which of FR-PLN-002's shapes a period was chosen as.
///
/// Carried so a saved plan can say "a month" rather than only "1–30
/// September" — `money_plans.period_type`'s check constraint, in the same
/// order.
enum PlanPeriodType {
  /// One day.
  day,

  /// One week.
  week,

  /// One calendar month.
  month,

  /// One calendar year.
  year,

  /// "The next N days".
  customDays,

  /// Any start and end.
  customRange,
}

/// How much of one calendar month a [PlanPeriod] covers.
class MonthCoverage extends Equatable {
  /// Creates a coverage.
  const MonthCoverage({
    required this.year,
    required this.month,
    required this.days,
    required this.fraction,
  });

  /// The calendar year.
  final int year;

  /// The calendar month, 1–12.
  final int month;

  /// How many of the period's days fall in this month.
  final int days;

  /// [days] over the month's length: 1.0 for a whole month.
  final double fraction;

  @override
  List<Object?> get props => [year, month, days, fraction];
}

/// The days a plan is for, both ends **inclusive** whole days. FR-PLN-002.
///
/// The statistics beneath a plan are per *month*, and a period is rarely a
/// month: a week straddles two, a year holds twelve, fifteen days is half
/// of one. [monthCoverage] is how a monthly figure becomes a figure for the
/// period — each month it touches, weighted by the share of that month it
/// covers — so a week in late November is 3/30 of November's budget plus
/// 4/31 of December's, with December's seasonal multiplier on its own days
/// only (FR-PLN-007).
class PlanPeriod extends Equatable {
  /// Creates a period from [from] to [to], inclusive. Any time of day on
  /// either end is ignored. FR-PLN-002's "Custom date range" unless [type]
  /// says otherwise — the named factories set it.
  PlanPeriod({
    required DateTime from,
    required DateTime to,
    this.type = PlanPeriodType.customRange,
  }) : from = DateTime(from.year, from.month, from.day),
       to = DateTime(to.year, to.month, to.day);

  /// The single day [date] falls on. FR-PLN-002's "Day".
  factory PlanPeriod.day(DateTime date) =>
      PlanPeriod(from: date, to: date, type: PlanPeriodType.day);

  /// The whole week [date] falls in, starting on [firstWeekday] (a
  /// `DateTime` weekday constant, Monday until FR-SET-004 makes it a
  /// setting in Sprint 7). FR-PLN-002's "Week".
  factory PlanPeriod.week(DateTime date, {int firstWeekday = DateTime.monday}) {
    final start = DateTime(date.year, date.month, date.day);
    final offset = (start.weekday - firstWeekday + 7) % 7;
    final from = DateTime(start.year, start.month, start.day - offset);
    return PlanPeriod(
      from: from,
      to: DateTime(from.year, from.month, from.day + 6),
      type: PlanPeriodType.week,
    );
  }

  /// The whole of one calendar month. FR-PLN-002's "Month".
  factory PlanPeriod.month(int year, int month) => PlanPeriod(
    from: DateTime(year, month),
    to: DateTime(year, month + 1, 0),
    type: PlanPeriodType.month,
  );

  /// The whole of one calendar year. FR-PLN-002's "Year".
  factory PlanPeriod.year(int year) => PlanPeriod(
    from: DateTime(year),
    to: DateTime(year, 12, 31),
    type: PlanPeriodType.year,
  );

  /// [days] days starting on [start]. FR-PLN-002's "Custom number of days".
  factory PlanPeriod.days(DateTime start, int days) => PlanPeriod(
    from: start,
    to: DateTime(start.year, start.month, start.day + days - 1),
    type: PlanPeriodType.customDays,
  );

  /// First day.
  final DateTime from;

  /// Last day.
  final DateTime to;

  /// Which shape this was chosen as.
  final PlanPeriodType type;

  /// True when the period runs backwards.
  bool get isInverted => from.isAfter(to);

  /// How many days the period holds, both ends counted.
  ///
  /// Calendar days rather than a `Duration`, which a daylight-saving change
  /// would put an hour out.
  int get days => isInverted
      ? 0
      : DateTime.utc(
              to.year,
              to.month,
              to.day,
            ).difference(DateTime.utc(from.year, from.month, from.day)).inDays +
            1;

  /// Every calendar month the period touches, in order, with the share of
  /// each it covers.
  List<MonthCoverage> get monthCoverage {
    if (isInverted) return const [];
    final coverage = <MonthCoverage>[];
    var cursor = DateTime(from.year, from.month);
    while (!cursor.isAfter(to)) {
      final monthEnd = DateTime(cursor.year, cursor.month + 1, 0);
      final first = from.isAfter(cursor) ? from : cursor;
      final last = to.isBefore(monthEnd) ? to : monthEnd;
      final days = last.day - first.day + 1;
      coverage.add(
        MonthCoverage(
          year: cursor.year,
          month: cursor.month,
          days: days,
          fraction: days / monthEnd.day,
        ),
      );
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return coverage;
  }

  /// The period's length in months, fractional: 1.0 for any whole month,
  /// 12.0 for a year, about 0.23 for a week.
  double get months => monthCoverage.fold(0.0, (sum, m) => sum + m.fraction);

  @override
  List<Object?> get props => [from, to, type];
}
