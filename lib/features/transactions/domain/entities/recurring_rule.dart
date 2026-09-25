import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'transaction.dart';

/// How often a recurring rule repeats. FR-EXP-008, FR-INC-004.
///
/// The five options FR-EXP-008 lists — Daily, Weekly, Monthly, Yearly and
/// Custom interval (N days) — and FR-INC-004 reuses for income.
enum RecurrenceFrequency {
  /// Every day.
  daily,

  /// Every week, on [RecurringRule.dayOfWeek].
  weekly,

  /// Every month, on [RecurringRule.dayOfMonth].
  monthly,

  /// Every year, on the anniversary of [RecurringRule.startDate].
  yearly,

  /// Every [RecurringRule.intervalDays] days.
  customDays,
}

/// A transaction that repeats. FR-EXP-008, FR-INC-004.
///
/// **The rule holds the schedule, not the money.** Amount, category, account
/// and note live on a template transaction ([templateTransactionId]) the
/// rule copies — DBD §3.6's design, which E-03's Amendment A adopted over
/// E-03's own. The template is the series' first entry, a real row in the
/// ledger, so editing it is how the series' future entries change.
///
/// **Dates are local calendar days**, like `Transaction.date`: midnight,
/// no time. Every date this class returns is built with the `DateTime(y, m,
/// d)` constructor, which counts calendar days and is not moved by a
/// daylight-saving change the way adding a `Duration` of 24 hours is.
class RecurringRule extends Equatable {
  /// Creates a rule as stored. Prefer [RecurringRule.startingOn] for a new
  /// one, which derives the day it recurs on and its first due date.
  const RecurringRule({
    required this.frequency,
    required this.startDate,
    required this.nextDueDate,
    this.id,
    this.templateTransactionId,
    this.intervalDays,
    this.dayOfWeek,
    this.dayOfMonth,
    this.endDate,
    this.lastCreatedAt,
    this.isActive = true,
  });

  /// A new rule whose first entry is on [startDate].
  ///
  /// The day a weekly or monthly rule recurs on is the start's own — a rent
  /// paid on the 5th repeats on the 5th — and the first due date is the
  /// occurrence after the start, because the start is the template itself
  /// and is written with the rule.
  ///
  /// Does not refuse anything: a rule with a [problem] — a monthly start
  /// past the 28th, a custom interval under a day — is returned with its
  /// next due date left on the start, unscheduled, so a caller can ask it
  /// what is wrong. `CreateRecurringRule.validate` does exactly that.
  factory RecurringRule.startingOn(
    DateTime startDate, {
    required RecurrenceFrequency frequency,
    int? intervalDays,
    DateTime? endDate,
  }) {
    final start = _day(startDate);
    final unscheduled = RecurringRule(
      frequency: frequency,
      startDate: start,
      nextDueDate: start,
      intervalDays: frequency == RecurrenceFrequency.customDays
          ? intervalDays
          : null,
      dayOfWeek: frequency == RecurrenceFrequency.weekly ? start.weekday : null,
      dayOfMonth: frequency == RecurrenceFrequency.monthly ? start.day : null,
      endDate: endDate == null ? null : _day(endDate),
    );
    if (unscheduled.problem != null) return unscheduled;
    return unscheduled.copyWith(nextDueDate: unscheduled.nextAfter(start));
  }

  /// The largest [dayOfMonth] a monthly rule may name.
  ///
  /// E-03: a rule for the 31st would skip every shorter month. The schema's
  /// CHECK holds the same bound, and it matches FR-SET-004's first day of
  /// the month.
  static const int maxDayOfMonth = 28;

  /// Row id, null before it is saved.
  final int? id;

  /// The transaction each entry copies. Null only when there is nothing
  /// left to copy — the template was deleted with no other entry in the
  /// series to take its place (E-36) — and such a rule is never active.
  final int? templateTransactionId;

  /// How often it repeats.
  final RecurrenceFrequency frequency;

  /// Days between entries, for [RecurrenceFrequency.customDays] only.
  final int? intervalDays;

  /// The weekday a weekly rule falls on, as Dart numbers it:
  /// [DateTime.monday] (1) to [DateTime.sunday] (7). Null otherwise.
  ///
  /// The column numbers the week from Sunday at zero, as `users` does; the
  /// model converts, so nothing above `data/` sees two conventions.
  final int? dayOfWeek;

  /// The day of the month a monthly rule falls on, 1 to [maxDayOfMonth].
  /// Null otherwise.
  final int? dayOfMonth;

  /// The template's own date: the series' first entry.
  final DateTime startDate;

  /// The last day an entry may fall on, inclusive. Null for open-ended.
  final DateTime? endDate;

  /// The date of the next entry to post.
  ///
  /// Moved forward in the same database transaction as the entries it
  /// posts, and only if it still holds the date that was read — which is
  /// what stops an entry being posted twice.
  final DateTime nextDueDate;

  /// When entries were last posted for this rule. Null until the first
  /// catch-up that posted one.
  final DateTime? lastCreatedAt;

  /// Whether the rule still posts. False once paused or ended.
  final bool isActive;

  /// Why this rule cannot be scheduled, or null when it can.
  ///
  /// The schema enforces most of this and not all of it: nothing stops a
  /// `custom_days` interval of zero, which would never move forward, or a
  /// weekly rule with no weekday. A rule that fails here is refused by the
  /// use cases rather than looped over.
  String? get problem {
    switch (frequency) {
      case RecurrenceFrequency.customDays:
        final interval = intervalDays;
        if (interval == null || interval < 1) {
          return 'A custom repeat needs an interval of at least one day.';
        }
      case RecurrenceFrequency.weekly:
        final weekday = dayOfWeek;
        if (weekday != null &&
            (weekday < DateTime.monday || weekday > DateTime.sunday)) {
          return 'A weekly repeat needs a day of the week.';
        }
      case RecurrenceFrequency.monthly:
        final day = dayOfMonth;
        if (day != null && (day < 1 || day > maxDayOfMonth)) {
          return 'A monthly repeat can fall on the 1st to the '
              '${maxDayOfMonth}th, so it lands in every month.';
        }
      case RecurrenceFrequency.daily:
      case RecurrenceFrequency.yearly:
        break;
    }
    final end = endDate;
    if (end != null && end.isBefore(startDate)) {
      return 'A repeat cannot end before it starts.';
    }
    return null;
  }

  /// The first date this rule falls on strictly after [date].
  ///
  /// Weekly and monthly rules land on their own day whatever [date] is, so
  /// a date between two entries gives the next entry rather than [date]
  /// plus a period. A yearly rule lands on the start's anniversary; one
  /// started on 29 February falls on the 28th in a year without one and
  /// goes back to the 29th in the next leap year, because each anniversary
  /// is taken from the start and not from the entry before it.
  ///
  /// A weekly or monthly rule stored without its day — the DBD's shape had
  /// neither column — recurs on the start's own day.
  ///
  /// Only meaningful on a rule with no [problem].
  DateTime nextAfter(DateTime date) {
    final d = _day(date);
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return DateTime(d.year, d.month, d.day + 1);
      case RecurrenceFrequency.customDays:
        return DateTime(d.year, d.month, d.day + intervalDays!);
      case RecurrenceFrequency.weekly:
        final weekday = dayOfWeek ?? startDate.weekday;
        return DateTime(
          d.year,
          d.month,
          d.day + _daysAhead(d.weekday, weekday),
        );
      case RecurrenceFrequency.monthly:
        final day = dayOfMonth ?? math.min(startDate.day, maxDayOfMonth);
        return d.day < day
            ? DateTime(d.year, d.month, day)
            : DateTime(d.year, d.month + 1, day);
      case RecurrenceFrequency.yearly:
        final thisYear = _anniversaryIn(d.year);
        return thisYear.isAfter(d) ? thisYear : _anniversaryIn(d.year + 1);
    }
  }

  /// Every entry due on or before [today], and where the rule stands after
  /// them.
  ///
  /// From [nextDueDate] forward, each date [nextAfter] the last, stopping
  /// after [today] or after [endDate], whichever comes first. **No cap**:
  /// a rule nobody opened the app for in three months posts three months
  /// of entries, because the ledger should say what happened.
  ///
  /// Only meaningful on a rule with no [problem].
  RecurrenceCatchUp catchUp(DateTime today) {
    final last = _day(today);
    final dates = <DateTime>[];
    var next = nextDueDate;
    while (!next.isAfter(last) && !_isPastEnd(next)) {
      dates.add(next);
      next = nextAfter(next);
    }
    return RecurrenceCatchUp(
      dates: dates,
      nextDueDate: next,
      ended: _isPastEnd(next),
    );
  }

  /// The entry this rule posts on [date], copied from [template].
  ///
  /// Everything that says what the money was — account, category, amount,
  /// type, time of day, note — comes from the template; the date is the
  /// entry's own, and the link back to the rule is set so the entry reads
  /// as generated (`is_recurring`) and "stop this repeating" has something
  /// to act on. A receipt link is not copied: next month's rent has no
  /// photo of this month's.
  Transaction entryOn(DateTime date, Transaction template) => Transaction(
    accountId: template.accountId,
    categoryId: template.categoryId,
    amountCents: template.amountCents,
    type: template.type,
    date: _day(date),
    time: template.time,
    note: template.note,
    recurringRuleId: id,
    isRecurring: true,
  );

  /// A copy with the given fields replaced.
  RecurringRule copyWith({
    int? id,
    int? templateTransactionId,
    DateTime? nextDueDate,
    DateTime? lastCreatedAt,
    bool? isActive,
  }) => RecurringRule(
    id: id ?? this.id,
    templateTransactionId: templateTransactionId ?? this.templateTransactionId,
    frequency: frequency,
    intervalDays: intervalDays,
    dayOfWeek: dayOfWeek,
    dayOfMonth: dayOfMonth,
    startDate: startDate,
    endDate: endDate,
    nextDueDate: nextDueDate ?? this.nextDueDate,
    lastCreatedAt: lastCreatedAt ?? this.lastCreatedAt,
    isActive: isActive ?? this.isActive,
  );

  bool _isPastEnd(DateTime date) {
    final end = endDate;
    return end != null && date.isAfter(end);
  }

  DateTime _anniversaryIn(int year) {
    // Day 0 of the next month is the last day of this one.
    final lastDay = DateTime(year, startDate.month + 1, 0).day;
    return DateTime(year, startDate.month, math.min(startDate.day, lastDay));
  }

  /// Days from weekday [from] forward to the next [to], 1 to 7 — never 0,
  /// because the next entry is strictly after the date asked about.
  static int _daysAhead(int from, int to) => (to - from + 6) % 7 + 1;

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  List<Object?> get props => [
    id,
    templateTransactionId,
    frequency,
    intervalDays,
    dayOfWeek,
    dayOfMonth,
    startDate,
    endDate,
    nextDueDate,
    lastCreatedAt,
    isActive,
  ];
}

/// What catching a rule up comes to. See [RecurringRule.catchUp].
class RecurrenceCatchUp extends Equatable {
  /// Creates a catch-up result.
  const RecurrenceCatchUp({
    required this.dates,
    required this.nextDueDate,
    required this.ended,
  });

  /// Every entry to post, oldest first. Empty when nothing is due.
  final List<DateTime> dates;

  /// Where the rule's next due date moves to once [dates] are posted.
  final DateTime nextDueDate;

  /// True when [nextDueDate] is past the rule's end, so the series is over
  /// and the rule stops.
  final bool ended;

  @override
  List<Object?> get props => [dates, nextDueDate, ended];
}

/// A rule that is due, with the template it copies.
///
/// Read together because a catch-up needs both, and reading the template
/// through a second query per rule would be one round trip per rule on the
/// launch path.
class DueRecurringRule extends Equatable {
  /// Creates a due rule.
  const DueRecurringRule({required this.rule, required this.template});

  /// The rule.
  final RecurringRule rule;

  /// The transaction it copies. Null when the rule has none (E-36), which
  /// the catch-up reports rather than posts.
  final Transaction? template;

  @override
  List<Object?> get props => [rule, template];
}
