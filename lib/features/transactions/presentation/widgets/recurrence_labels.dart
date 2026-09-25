/// How a recurring rule is put into words. FR-EXP-008, FR-INC-004.
///
/// One place for every sentence the entry screen's repeat section and the
/// rules list say about a schedule, so the two screens cannot describe the
/// same rule two ways. Pure functions: tested without a widget.
library;

import 'package:intl/intl.dart';

import '../../domain/entities/recurring_rule.dart';

/// The chip label for [frequency] on the entry screen.
String frequencyLabel(RecurrenceFrequency frequency) => switch (frequency) {
  RecurrenceFrequency.daily => 'Daily',
  RecurrenceFrequency.weekly => 'Weekly',
  RecurrenceFrequency.monthly => 'Monthly',
  RecurrenceFrequency.yearly => 'Yearly',
  RecurrenceFrequency.customDays => 'Every N days',
};

/// [rule]'s schedule as a phrase: "Every Wednesday", "Monthly on the 5th".
///
/// Read off the rule's own anchors, which `RecurringRule.startingOn` takes
/// from the start date, so the phrase says the day the rule will actually
/// post on.
String describeRecurrence(RecurringRule rule) {
  switch (rule.frequency) {
    case RecurrenceFrequency.daily:
      return 'Every day';
    case RecurrenceFrequency.weekly:
      final weekday = rule.dayOfWeek ?? rule.startDate.weekday;
      // 1 January 2024 was a Monday, so day `weekday` of that week is the
      // weekday itself.
      return 'Every ${DateFormat.EEEE().format(DateTime(2024, 1, weekday))}';
    case RecurrenceFrequency.monthly:
      final day = rule.dayOfMonth ?? rule.startDate.day;
      return 'Monthly on the ${ordinal(day)}';
    case RecurrenceFrequency.yearly:
      return 'Yearly on ${DateFormat.MMMMd().format(rule.startDate)}';
    case RecurrenceFrequency.customDays:
      final interval = rule.intervalDays ?? 1;
      return interval == 1 ? 'Every day' : 'Every $interval days';
  }
}

/// Where [rule] stands on [today], as the rules list's second line.
String describeStatus(RecurringRule rule, DateTime today) {
  final date = DateFormat.yMMMd();
  return switch (rule.statusOn(today)) {
    RecurrenceStatus.active => 'Next on ${date.format(rule.nextDueDate)}',
    RecurrenceStatus.overdue =>
      'Overdue since ${date.format(rule.nextDueDate)}. It will try again '
          'next time the app opens.',
    RecurrenceStatus.paused => 'Paused',
    RecurrenceStatus.ended => 'Ended',
    RecurrenceStatus.noTemplate => 'Stopped: its first entry was deleted',
  };
}

/// 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st, 22nd, 23rd … 28th.
String ordinal(int n) {
  final lastTwo = n % 100;
  if (lastTwo >= 11 && lastTwo <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}
