import 'package:equatable/equatable.dart';

import 'plan_allocation.dart';
import 'plan_period.dart';

/// FR-PLN-013's three colours, as what they mean rather than as colours.
enum TrackingStatus {
  /// Under 80% of the allocation spent. Green.
  onTrack,

  /// 80–99% spent. Yellow.
  warning,

  /// The allocation is spent, or more than spent. Red.
  exceeded,
}

/// One allocation's spend read against its budget and the calendar.
/// FR-PLN-013.
///
/// Pure arithmetic over a [PlanAllocation], its plan's [PlanPeriod] and a
/// date, so it is testable with no clock and no database: the screen
/// passes `DateTime.now()`, a test passes whatever day it is asserting
/// about. Every figure is integer cents (E-06); the percentage is an
/// integer too, floored, so a row is never labelled "100%" while still
/// yellow.
class AllocationProgress extends Equatable {
  /// Creates a progress reading by hand. Prefer [AllocationProgress.of].
  const AllocationProgress({
    required this.allocation,
    required this.percentUsed,
    required this.status,
    required this.elapsedDays,
    required this.totalDays,
    required this.projectedCents,
  });

  /// [allocation] on [today], for a plan over [period].
  ///
  /// **The percentage** is `spent / allocated`. An allocation of zero has
  /// no percentage; it reads as exceeded the moment anything is spent
  /// against it and as 0% otherwise.
  ///
  /// **The status** follows the requirement's bands: green below 80%,
  /// yellow from 80% up to but not including 100%, red at 100% and above
  /// — "exceeded" includes exactly spent, since a budget with nothing
  /// left is not on track.
  ///
  /// **The projection** extrapolates the spend so far to the whole period
  /// by elapsed days: `spent × totalDays / elapsedDays`, where the days
  /// elapsed run from the period's first day to [today], both counted, so
  /// on the first day one day has elapsed and the projection is thirty
  /// times the day's spend. Before the period starts nothing has elapsed
  /// and there is nothing to extrapolate from — [projectedCents] is null.
  /// After it ends the projection is the spend itself.
  factory AllocationProgress.of(
    PlanAllocation allocation,
    PlanPeriod period,
    DateTime today,
  ) {
    final totalDays = period.days;
    final day = DateTime(today.year, today.month, today.day);
    final elapsed = day.isBefore(period.from)
        ? 0
        : (PlanPeriod(from: period.from, to: day).days).clamp(0, totalDays);

    final spent = allocation.spentCents;
    final allocated = allocation.allocatedCents;
    return AllocationProgress(
      allocation: allocation,
      percentUsed: percentOf(spentCents: spent, allocatedCents: allocated),
      status: statusOf(spentCents: spent, allocatedCents: allocated),
      elapsedDays: elapsed,
      totalDays: totalDays,
      projectedCents: elapsed == 0 ? null : spent * totalDays ~/ elapsed,
    );
  }

  /// Whole percent of [allocatedCents] that [spentCents] is, floored. An
  /// allocation of zero reads 100 once anything is spent against it, 0
  /// otherwise.
  static int percentOf({
    required int spentCents,
    required int allocatedCents,
  }) => allocatedCents > 0
      ? spentCents * 100 ~/ allocatedCents
      : (spentCents > 0 ? 100 : 0);

  /// FR-PLN-013's band for [spentCents] against [allocatedCents].
  ///
  /// Public and static so FR-SET-007's budget alerts read the same bands the
  /// tracking bar is drawn in: a notification saying 80% and a row still
  /// green would be two rules for one number.
  static TrackingStatus statusOf({
    required int spentCents,
    required int allocatedCents,
  }) => allocatedCents == 0
      ? (spentCents > 0 ? TrackingStatus.exceeded : TrackingStatus.onTrack)
      : spentCents >= allocatedCents
      ? TrackingStatus.exceeded
      : spentCents * 100 >= allocatedCents * 80
      ? TrackingStatus.warning
      : TrackingStatus.onTrack;

  /// The row this reads.
  final PlanAllocation allocation;

  /// Whole percent of the allocation spent, floored. Not capped: 150 is a
  /// row half again over.
  final int percentUsed;

  /// Which of the three colours the row shows.
  final TrackingStatus status;

  /// Days of the period up to and including today, 0 before it starts.
  final int elapsedDays;

  /// Days in the period.
  final int totalDays;

  /// What the period's spend would be at today's rate, or null before the
  /// period has begun.
  final int? projectedCents;

  /// How far [projectedCents] lands from the allocation: positive is a
  /// projected overspend, negative a projected underspend, null when there
  /// is no projection.
  int? get projectedDifferenceCents => switch (projectedCents) {
    null => null,
    final p => p - allocation.allocatedCents,
  };

  /// What is left, negative once exceeded.
  int get remainingCents => allocation.allocatedCents - allocation.spentCents;

  @override
  List<Object?> get props => [
    allocation,
    percentUsed,
    status,
    elapsedDays,
    totalDays,
    projectedCents,
  ];
}
