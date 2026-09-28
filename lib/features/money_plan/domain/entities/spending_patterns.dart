import 'package:equatable/equatable.dart';

import '../../../../core/ports/daily_spending_reader.dart';
import 'lookback_window.dart';

/// Which side of a [PatternComparison] spends more a day.
enum PatternLean {
  /// The first side named: weekdays, or the start of the month.
  first,

  /// The second side named: the weekend, or the end of the month.
  second,
}

/// The average spent a day on two kinds of day. FR-PLN-006.
class PatternComparison extends Equatable {
  /// Creates a comparison.
  const PatternComparison({
    required this.firstDailyCents,
    required this.secondDailyCents,
  });

  /// How far above the other one side has to be to count as a pattern, in
  /// percent. Below it the difference is a week or two of ordinary noise,
  /// and naming it would tell someone about a habit they do not have.
  static const int thresholdPercent = 25;

  /// The average a day on the first kind of day, in minor units.
  final int firstDailyCents;

  /// The average a day on the second kind of day, in minor units.
  final int secondDailyCents;

  int get _high =>
      firstDailyCents > secondDailyCents ? firstDailyCents : secondDailyCents;

  int get _low =>
      firstDailyCents > secondDailyCents ? secondDailyCents : firstDailyCents;

  /// The side that spends notably more a day, or null when neither does.
  ///
  /// Compared in integers — `high * 100 >= low * (100 + threshold)` — so the
  /// edge is exact rather than a float's idea of it.
  PatternLean? get lean {
    if (_high == 0) return null;
    if (_high * 100 < _low * (100 + thresholdPercent)) return null;
    return firstDailyCents > secondDailyCents
        ? PatternLean.first
        : PatternLean.second;
  }

  /// How much more a day the side that [lean]s spends, in whole percent,
  /// rounded down. Null when there is no lean, or the other side spent
  /// nothing, where a percentage would be infinite.
  int? get percentMore {
    if (lean == null || _low == 0) return null;
    return (_high - _low) * 100 ~/ _low;
  }

  @override
  List<Object?> get props => [firstDailyCents, secondDailyCents];
}

/// When in the week and the month the money goes. FR-PLN-006.
///
/// Two of the SRS's four patterns: weekday against weekend, and the start of
/// a month against its end. The other two are elsewhere or nowhere: a
/// seasonal cycle is FR-PLN-004's Seasonal class, and event-based spikes are
/// not built.
///
/// Every day of the window counts, including the days nothing was spent: a
/// weekend of nothing is part of what a weekend costs. What does not count
/// is a category spent on no more than [billDaysPerMonth] days in each month
/// it appears in — a rent, a subscription, a one-off: its day is a due date
/// or an accident, not a habit. Counted in, a rent paid on the 1st made the
/// first ten days of a month look five times dearer than the last ten.
/// The month's start is
/// its first ten days and its end is its last ten, the middle left out so
/// the two do not blur into each other in a short month. Calendar months,
/// as the rest of the plan's statistics are.
class SpendingPatterns extends Equatable {
  /// Creates the patterns.
  const SpendingPatterns({
    required this.week,
    required this.month,
    required this.spendingDays,
    this.leftOut = const {},
  });

  /// Days a month's start or end runs to.
  static const int edgeDays = 10;

  /// How many days with any spending a pattern needs to be read at all.
  /// Fewer, and one large purchase decides the answer.
  static const int minSpendingDays = 20;

  /// The most days in a month a category can be spent on and still be a
  /// bill rather than a habit. A rent is one; a bill paid in two parts, two.
  /// Fuel every nine days is three, and a habit.
  static const int billDaysPerMonth = 2;

  /// Weekdays first, the weekend (Saturday and Sunday) second.
  final PatternComparison week;

  /// The first [edgeDays] of each month first, the last [edgeDays] second.
  final PatternComparison month;

  /// How many days in the window had any spending that counted.
  final int spendingDays;

  /// The categories left out as bills or one-offs, by id.
  final Set<int> leftOut;

  /// Whether there is enough history for [week] and [month] to mean
  /// anything.
  bool get hasEnoughHistory => spendingDays >= minSpendingDays;

  /// The patterns in [days] over [window]. Rows outside it are ignored.
  factory SpendingPatterns.from(
    LookbackWindow window,
    Iterable<DailySpending> days,
  ) {
    final inWindow = [
      for (final d in days)
        if (DateTime(d.day.year, d.day.month, d.day.day) case final day
            when !day.isBefore(window.from) && !day.isAfter(window.to))
          (day: day, categoryId: d.categoryId, cents: d.amountCents),
    ];

    final daysOf = <int, Set<DateTime>>{};
    final monthsOf = <int, Set<DateTime>>{};
    for (final d in inWindow) {
      (daysOf[d.categoryId] ??= {}).add(d.day);
      (monthsOf[d.categoryId] ??= {}).add(DateTime(d.day.year, d.day.month));
    }
    final leftOut = {
      for (final id in daysOf.keys)
        if (daysOf[id]!.length <= billDaysPerMonth * monthsOf[id]!.length) id,
    };

    final spent = <DateTime, int>{};
    for (final d in inWindow) {
      if (leftOut.contains(d.categoryId)) continue;
      spent[d.day] = (spent[d.day] ?? 0) + d.cents;
    }

    var weekdayCents = 0, weekdays = 0, weekendCents = 0, weekends = 0;
    var startCents = 0, starts = 0, endCents = 0, ends = 0;
    // Day by day through the calendar, not by adding 24 hours, which a
    // daylight-saving change would knock off midnight.
    for (
      var day = window.from;
      !day.isAfter(window.to);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final cents = spent[day] ?? 0;
      if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
        weekendCents += cents;
        weekends++;
      } else {
        weekdayCents += cents;
        weekdays++;
      }
      final monthLength = DateTime(day.year, day.month + 1, 0).day;
      if (day.day <= edgeDays) {
        startCents += cents;
        starts++;
      } else if (day.day > monthLength - edgeDays) {
        endCents += cents;
        ends++;
      }
    }

    return SpendingPatterns(
      week: PatternComparison(
        firstDailyCents: _average(weekdayCents, weekdays),
        secondDailyCents: _average(weekendCents, weekends),
      ),
      month: PatternComparison(
        firstDailyCents: _average(startCents, starts),
        secondDailyCents: _average(endCents, ends),
      ),
      spendingDays: spent.values.where((c) => c > 0).length,
      leftOut: leftOut,
    );
  }

  /// To the nearest minor unit, halves up; amounts are never negative.
  static int _average(int total, int days) =>
      days == 0 ? 0 : (total * 2 + days) ~/ (days * 2);

  @override
  List<Object?> get props => [week, month, spendingDays, leftOut];
}
