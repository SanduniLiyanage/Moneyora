/// One calendar month of daily spending, ready to draw as a heatmap.
/// FR-RPT-009.
///
/// Always a whole month, whatever FR-RPT-002's picker has selected: a heatmap
/// is a grid of days, and a Year or a Day under it is a different picture,
/// not a longer or shorter version of this one. The picker's anchor says
/// *which* month; the period chips say nothing to this card.
library;

import 'package:equatable/equatable.dart';

/// Which month to draw, and which account to count. FR-RPT-009, FR-RPT-003.
class SpendingCalendarQuery extends Equatable {
  /// Creates a query for the month [anchor] falls in.
  SpendingCalendarQuery({required DateTime anchor, this.accountId})
    : year = anchor.year,
      month = anchor.month;

  /// Creates a query for [year]/[month] directly.
  const SpendingCalendarQuery.of(this.year, this.month, {this.accountId});

  /// The calendar year.
  final int year;

  /// The calendar month, 1–12.
  final int month;

  /// The one account to count, or null for All Accounts. FR-RPT-003.
  final int? accountId;

  @override
  List<Object?> get props => [year, month, accountId];
}

/// A month's spending, one amount per day. FR-RPT-009.
class SpendingCalendar extends Equatable {
  /// Creates a calendar. [amountsCents] has one entry per day of the month,
  /// index 0 being the 1st.
  const SpendingCalendar({
    required this.year,
    required this.month,
    required this.amountsCents,
  });

  /// How many intensity steps the ramp has, above "nothing spent".
  static const int levels = 5;

  /// The calendar year.
  final int year;

  /// The calendar month, 1–12.
  final int month;

  /// What was spent each day, in integer minor units (E-06); zero for a
  /// quiet day. Length is the number of days in the month.
  final List<int> amountsCents;

  /// Days in the month.
  int get dayCount => amountsCents.length;

  /// The largest single day — the ceiling every other day is shaded against.
  ///
  /// Relative to this month rather than a fixed figure or a cross-month one:
  /// every month then has a darkest cell, so the grid always reads as a
  /// distribution rather than as uniformly pale in a quiet month.
  int get maxCents => amountsCents.fold(0, (m, c) => c > m ? c : m);

  /// The whole month's spending.
  int get totalCents => amountsCents.fold(0, (sum, c) => sum + c);

  /// True when nothing was spent all month.
  bool get isEmpty => maxCents == 0;

  /// What was spent on [day] (1-based).
  int amountOn(int day) => amountsCents[day - 1];

  /// The intensity of [day] (1-based): 0 for nothing spent, then 1 to
  /// [levels] as an even split of `0 < amount <= maxCents`, so the largest
  /// day is always [levels].
  int levelOf(int day) {
    final cents = amountOn(day);
    if (cents == 0) return 0;
    return (cents * levels / maxCents).ceil().clamp(1, levels);
  }

  @override
  List<Object?> get props => [year, month, amountsCents];
}
