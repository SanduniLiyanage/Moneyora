/// What period the analytics surfaces report over. FR-RPT-002.
///
/// The requirement names seven filters — Day, Week, Month, Year, All, Custom
/// Interval, Choose Date — which are not seven independent modes. Six of them
/// choose a *shape* of period; "Choose Date" chooses which date that shape
/// wraps around. So this is one [AnalyticsPeriod] plus one [anchor], and the
/// range falls out of the pair. Modelling "Choose Date" as a seventh shape
/// would have meant a mode that answers "which week?" with nothing.
library;

import 'package:equatable/equatable.dart';

import '../repositories/analytics_repository.dart';

/// The shape of an analytics period. FR-RPT-002.
enum AnalyticsPeriod {
  /// One calendar day.
  day,

  /// One calendar week.
  week,

  /// One calendar month.
  month,

  /// One calendar year.
  year,

  /// Every transaction on record.
  all,

  /// An arbitrary interval the user picked. FR-RPT-002's "Custom Interval".
  custom,
}

/// A chosen [AnalyticsPeriod], the date it is anchored to, and — for
/// [AnalyticsPeriod.custom] only — the interval the user picked.
///
/// Immutable, and [range] is a pure function of the three fields: no clock is
/// read here, so a test can state the day it is and get the same answer twice.
class PeriodSelection extends Equatable {
  /// Creates a selection. [anchor] is the date the period wraps around —
  /// FR-RPT-002's "Choose Date" — and is ignored by
  /// [AnalyticsPeriod.all] and [AnalyticsPeriod.custom].
  const PeriodSelection({
    required this.period,
    required this.anchor,
    this.customRange,
  });

  /// The default the app opens on: the calendar month containing [today].
  ///
  /// Month rather than Day because it is the period the donut chart shipped
  /// with (FR-RPT-001), and changing what the home screen shows by default
  /// is not what adding a filter is for.
  factory PeriodSelection.monthOf(DateTime today) =>
      PeriodSelection(period: AnalyticsPeriod.month, anchor: today);

  /// Which shape of period is selected.
  final AnalyticsPeriod period;

  /// The date the period is anchored to — FR-RPT-002's "Choose Date".
  final DateTime anchor;

  /// The interval behind [AnalyticsPeriod.custom]; null for every other
  /// period, and null for `custom` only before one has been picked, in which
  /// case [range] falls back to the day [anchor] falls on.
  final DateRange? customRange;

  /// The period as a [DateRange] the analytics use cases can take.
  ///
  /// The one place a filter becomes a query parameter. An inverted
  /// [customRange] is *not* corrected here — it is passed through so that
  /// `GetSpendingByCategory.validate` refuses it and the screen shows that
  /// refusal, which is the existing convention for a bad range and the only
  /// one that tells the user anything. Silently swapping the ends would turn
  /// a mistake into a plausible-looking answer.
  DateRange get range => switch (period) {
    AnalyticsPeriod.day => DateRange.day(anchor),
    AnalyticsPeriod.week => DateRange.week(anchor),
    AnalyticsPeriod.month => DateRange.month(anchor.year, anchor.month),
    AnalyticsPeriod.year => DateRange.year(anchor.year),
    AnalyticsPeriod.all => DateRange.allTime(),
    AnalyticsPeriod.custom => customRange ?? DateRange.day(anchor),
  };

  /// This selection with [period] chosen, keeping the anchor and any custom
  /// interval already picked — switching to Week and back to Month must
  /// return to the month the user was looking at, not to today.
  PeriodSelection withPeriod(AnalyticsPeriod period) =>
      PeriodSelection(period: period, anchor: anchor, customRange: customRange);

  /// This selection re-anchored to [anchor]. FR-RPT-002's "Choose Date".
  PeriodSelection withAnchor(DateTime anchor) =>
      PeriodSelection(period: period, anchor: anchor, customRange: customRange);

  /// This selection switched to [AnalyticsPeriod.custom] over [range].
  PeriodSelection withCustomRange(DateRange range) => PeriodSelection(
    period: AnalyticsPeriod.custom,
    anchor: anchor,
    customRange: range,
  );

  @override
  List<Object?> get props => [period, anchor, customRange];
}
