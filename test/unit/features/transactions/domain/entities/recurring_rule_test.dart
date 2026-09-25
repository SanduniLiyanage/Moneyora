import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';

void main() {
  RecurringRule rule(
    RecurrenceFrequency frequency, {
    required DateTime start,
    DateTime? next,
    int? intervalDays,
    int? dayOfWeek,
    int? dayOfMonth,
    DateTime? end,
  }) => RecurringRule(
    id: 5,
    templateTransactionId: 9,
    frequency: frequency,
    startDate: start,
    nextDueDate: next ?? start,
    intervalDays: intervalDays,
    dayOfWeek: dayOfWeek,
    dayOfMonth: dayOfMonth,
    endDate: end,
  );

  group('startingOn', () {
    test('a daily rule is next due the day after its start', () {
      final r = RecurringRule.startingOn(
        DateTime(2026, 3, 31),
        frequency: RecurrenceFrequency.daily,
      );
      expect(r.startDate, DateTime(2026, 3, 31));
      expect(r.nextDueDate, DateTime(2026, 4));
      expect(r.isActive, isTrue);
    });

    test('a weekly rule recurs on its start weekday', () {
      // 2026-03-04 is a Wednesday.
      final r = RecurringRule.startingOn(
        DateTime(2026, 3, 4),
        frequency: RecurrenceFrequency.weekly,
      );
      expect(r.dayOfWeek, DateTime.wednesday);
      expect(r.dayOfMonth, isNull);
      expect(r.nextDueDate, DateTime(2026, 3, 11));
    });

    test('a monthly rule recurs on its start day', () {
      final r = RecurringRule.startingOn(
        DateTime(2026, 1, 5),
        frequency: RecurrenceFrequency.monthly,
      );
      expect(r.dayOfMonth, 5);
      expect(r.dayOfWeek, isNull);
      expect(r.nextDueDate, DateTime(2026, 2, 5));
    });

    test('a yearly rule is next due on the anniversary', () {
      final r = RecurringRule.startingOn(
        DateTime(2025, 6, 15),
        frequency: RecurrenceFrequency.yearly,
      );
      expect(r.nextDueDate, DateTime(2026, 6, 15));
    });

    test('a custom rule keeps its interval; others drop one', () {
      final custom = RecurringRule.startingOn(
        DateTime(2026, 1, 1),
        frequency: RecurrenceFrequency.customDays,
        intervalDays: 10,
      );
      expect(custom.intervalDays, 10);
      expect(custom.nextDueDate, DateTime(2026, 1, 11));

      final daily = RecurringRule.startingOn(
        DateTime(2026, 1, 1),
        frequency: RecurrenceFrequency.daily,
        intervalDays: 10,
      );
      expect(daily.intervalDays, isNull);
    });

    test('drops the time of day from the start and the end', () {
      final r = RecurringRule.startingOn(
        DateTime(2026, 1, 1, 23, 45),
        frequency: RecurrenceFrequency.daily,
        endDate: DateTime(2026, 2, 1, 8),
      );
      expect(r.startDate, DateTime(2026, 1, 1));
      expect(r.endDate, DateTime(2026, 2, 1));
    });

    test('a rule with a problem is left unscheduled, on its start', () {
      final r = RecurringRule.startingOn(
        DateTime(2026, 1, 31),
        frequency: RecurrenceFrequency.monthly,
      );
      expect(r.problem, isNotNull);
      expect(r.nextDueDate, DateTime(2026, 1, 31));

      // Would throw on the missing interval if it were scheduled.
      final custom = RecurringRule.startingOn(
        DateTime(2026, 1, 1),
        frequency: RecurrenceFrequency.customDays,
      );
      expect(custom.problem, isNotNull);
      expect(custom.nextDueDate, DateTime(2026, 1, 1));
    });
  });

  group('problem', () {
    final start = DateTime(2026, 1, 1);

    test('is null for a well-formed rule of every frequency', () {
      expect(rule(RecurrenceFrequency.daily, start: start).problem, isNull);
      expect(
        rule(RecurrenceFrequency.weekly, start: start, dayOfWeek: 7).problem,
        isNull,
      );
      expect(
        rule(RecurrenceFrequency.monthly, start: start, dayOfMonth: 28).problem,
        isNull,
      );
      expect(rule(RecurrenceFrequency.yearly, start: start).problem, isNull);
      expect(
        rule(
          RecurrenceFrequency.customDays,
          start: start,
          intervalDays: 1,
        ).problem,
        isNull,
      );
    });

    test('a custom rule needs an interval of at least one day', () {
      const message = 'A custom repeat needs an interval of at least one day.';
      expect(
        rule(RecurrenceFrequency.customDays, start: start).problem,
        message,
      );
      // The schema accepts zero; the rule would never move forward.
      expect(
        rule(
          RecurrenceFrequency.customDays,
          start: start,
          intervalDays: 0,
        ).problem,
        message,
      );
    });

    test('a monthly day past the 28th is refused (E-03)', () {
      expect(
        rule(RecurrenceFrequency.monthly, start: start, dayOfMonth: 29).problem,
        'A monthly repeat can fall on the 1st to the 28th, so it lands in '
        'every month.',
      );
      expect(
        rule(RecurrenceFrequency.monthly, start: start, dayOfMonth: 0).problem,
        isNotNull,
      );
    });

    test('a weekday outside Monday to Sunday is refused', () {
      expect(
        rule(RecurrenceFrequency.weekly, start: start, dayOfWeek: 0).problem,
        'A weekly repeat needs a day of the week.',
      );
      expect(
        rule(RecurrenceFrequency.weekly, start: start, dayOfWeek: 8).problem,
        isNotNull,
      );
    });

    test('an end before the start is refused; the same day is fine', () {
      expect(
        rule(
          RecurrenceFrequency.daily,
          start: start,
          end: DateTime(2025, 12, 31),
        ).problem,
        'A repeat cannot end before it starts.',
      );
      expect(
        rule(RecurrenceFrequency.daily, start: start, end: start).problem,
        isNull,
      );
    });
  });

  group('nextAfter', () {
    test('daily walks a whole year one calendar day at a time', () {
      final r = rule(RecurrenceFrequency.daily, start: DateTime(2026));
      var d = DateTime(2026);
      final seen = <DateTime>{};
      for (var i = 0; i < 365; i++) {
        d = r.nextAfter(d);
        seen.add(d);
        // Local midnight every time: a daylight-saving change must not
        // shift an entry onto 23:00 of the day before.
        expect(d.hour, 0);
      }
      expect(seen, hasLength(365));
      expect(d, DateTime(2027));
    });

    test('custom days adds the interval', () {
      final r = rule(
        RecurrenceFrequency.customDays,
        start: DateTime(2026, 1, 25),
        intervalDays: 10,
      );
      expect(r.nextAfter(DateTime(2026, 1, 25)), DateTime(2026, 2, 4));
    });

    test('weekly lands on its weekday from any day of the week', () {
      final r = rule(
        RecurrenceFrequency.weekly,
        start: DateTime(2026, 3, 4),
        dayOfWeek: DateTime.wednesday,
      );
      // Wednesday itself: the next one, never the same day.
      expect(r.nextAfter(DateTime(2026, 3, 4)), DateTime(2026, 3, 11));
      // Monday before it, and Thursday after it.
      expect(r.nextAfter(DateTime(2026, 3, 2)), DateTime(2026, 3, 4));
      expect(r.nextAfter(DateTime(2026, 3, 5)), DateTime(2026, 3, 11));
      // Across a month and a year boundary.
      expect(r.nextAfter(DateTime(2026, 12, 31)), DateTime(2027, 1, 6));
    });

    test('weekly on a Sunday', () {
      final r = rule(
        RecurrenceFrequency.weekly,
        start: DateTime(2026, 3, 1),
        dayOfWeek: DateTime.sunday,
      );
      expect(r.nextAfter(DateTime(2026, 3, 1)), DateTime(2026, 3, 8));
      expect(r.nextAfter(DateTime(2026, 3, 7)), DateTime(2026, 3, 8));
    });

    test('monthly lands on its day, this month or the next', () {
      final r = rule(
        RecurrenceFrequency.monthly,
        start: DateTime(2026, 1, 15),
        dayOfMonth: 15,
      );
      expect(r.nextAfter(DateTime(2026, 2, 3)), DateTime(2026, 2, 15));
      expect(r.nextAfter(DateTime(2026, 2, 15)), DateTime(2026, 3, 15));
      expect(r.nextAfter(DateTime(2026, 2, 20)), DateTime(2026, 3, 15));
      expect(r.nextAfter(DateTime(2026, 12, 15)), DateTime(2027, 1, 15));
    });

    test('monthly on the 28th reaches every month, February included', () {
      final r = rule(
        RecurrenceFrequency.monthly,
        start: DateTime(2026, 1, 28),
        dayOfMonth: 28,
      );
      var d = DateTime(2026, 1, 28);
      final months = <int>[];
      for (var i = 0; i < 12; i++) {
        d = r.nextAfter(d);
        expect(d.day, 28);
        months.add(d.month);
      }
      expect(months, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 1]);
    });

    test('yearly from 29 February falls on the 28th and returns to the '
        '29th', () {
      final r = rule(RecurrenceFrequency.yearly, start: DateTime(2024, 2, 29));
      var d = DateTime(2024, 2, 29);
      final dates = <DateTime>[];
      for (var i = 0; i < 4; i++) {
        d = r.nextAfter(d);
        dates.add(d);
      }
      expect(dates, [
        DateTime(2025, 2, 28),
        DateTime(2026, 2, 28),
        DateTime(2027, 2, 28),
        DateTime(2028, 2, 29),
      ]);
    });

    test('yearly from a date inside the year gives this year or the next', () {
      final r = rule(RecurrenceFrequency.yearly, start: DateTime(2025, 6, 15));
      expect(r.nextAfter(DateTime(2026, 1, 1)), DateTime(2026, 6, 15));
      expect(r.nextAfter(DateTime(2026, 6, 15)), DateTime(2027, 6, 15));
    });

    test('a weekly or monthly rule stored without its day recurs on the '
        'start day', () {
      // The DBD's shape had neither column.
      final weekly = rule(
        RecurrenceFrequency.weekly,
        start: DateTime(2026, 3, 4), // Wednesday
      );
      expect(weekly.nextAfter(DateTime(2026, 3, 4)), DateTime(2026, 3, 11));

      final monthly = rule(
        RecurrenceFrequency.monthly,
        start: DateTime(2026, 1, 10),
      );
      expect(monthly.nextAfter(DateTime(2026, 1, 10)), DateTime(2026, 2, 10));
    });

    test('ignores the time of day of the date asked about', () {
      final r = rule(RecurrenceFrequency.daily, start: DateTime(2026));
      expect(r.nextAfter(DateTime(2026, 5, 5, 23, 59)), DateTime(2026, 5, 6));
    });
  });

  group('catchUp', () {
    RecurringRule monthly({required DateTime next, DateTime? end}) => rule(
      RecurrenceFrequency.monthly,
      start: DateTime(2026, 1, 5),
      next: next,
      dayOfMonth: 5,
      end: end,
    );

    test('nothing is due before the next due date', () {
      final c = monthly(next: DateTime(2026, 6, 5))
          .catchUp(DateTime(2026, 6, 4));
      expect(c.dates, isEmpty);
      expect(c.nextDueDate, DateTime(2026, 6, 5));
      expect(c.ended, isFalse);
    });

    test('an entry due today is posted today', () {
      final c = monthly(next: DateTime(2026, 6, 5))
          .catchUp(DateTime(2026, 6, 5, 7, 30));
      expect(c.dates, [DateTime(2026, 6, 5)]);
      expect(c.nextDueDate, DateTime(2026, 7, 5));
      expect(c.ended, isFalse);
    });

    test('every missed entry is posted, oldest first', () {
      final c = monthly(next: DateTime(2026, 3, 5))
          .catchUp(DateTime(2026, 6, 20));
      expect(c.dates, [
        DateTime(2026, 3, 5),
        DateTime(2026, 4, 5),
        DateTime(2026, 5, 5),
        DateTime(2026, 6, 5),
      ]);
      expect(c.nextDueDate, DateTime(2026, 7, 5));
    });

    test('there is no cap on how far back a catch-up reaches', () {
      final daily = rule(
        RecurrenceFrequency.daily,
        start: DateTime(2024),
        next: DateTime(2024, 1, 2),
      );
      final c = daily.catchUp(DateTime(2025, 12, 31));
      // 2024 is a leap year: 365 days to its end from 2 Jan, then 365.
      expect(c.dates, hasLength(730));
      expect(c.dates.first, DateTime(2024, 1, 2));
      expect(c.dates.last, DateTime(2025, 12, 31));
      expect(c.nextDueDate, DateTime(2026));
    });

    test('the end date is inclusive, and the rule ends after it', () {
      final c = monthly(
        next: DateTime(2026, 3, 5),
        end: DateTime(2026, 4, 5),
      ).catchUp(DateTime(2026, 6, 20));
      expect(c.dates, [DateTime(2026, 3, 5), DateTime(2026, 4, 5)]);
      expect(c.nextDueDate, DateTime(2026, 5, 5));
      expect(c.ended, isTrue);
    });

    test('an end date still ahead does not end the rule', () {
      final c = monthly(
        next: DateTime(2026, 3, 5),
        end: DateTime(2026, 12, 31),
      ).catchUp(DateTime(2026, 3, 10));
      expect(c.dates, [DateTime(2026, 3, 5)]);
      expect(c.ended, isFalse);
    });

    test('a rule already past its end posts nothing and ends', () {
      final c = monthly(
        next: DateTime(2026, 5, 5),
        end: DateTime(2026, 5, 1),
      ).catchUp(DateTime(2026, 6, 20));
      expect(c.dates, isEmpty);
      expect(c.nextDueDate, DateTime(2026, 5, 5));
      expect(c.ended, isTrue);
    });
  });

  group('nextOnOrAfter', () {
    RecurringRule monthly(DateTime next) => rule(
      RecurrenceFrequency.monthly,
      start: DateTime(2026, 1, 5),
      next: next,
      dayOfMonth: 5,
    );

    test('steps over every date before the day', () {
      expect(
        monthly(DateTime(2026, 2, 5)).nextOnOrAfter(DateTime(2026, 6, 20)),
        DateTime(2026, 7, 5),
      );
    });

    test('keeps a date that falls on the day itself', () {
      expect(
        monthly(DateTime(2026, 2, 5)).nextOnOrAfter(DateTime(2026, 6, 5, 18)),
        DateTime(2026, 6, 5),
      );
    });

    test('keeps the next due date when it is already ahead', () {
      expect(
        monthly(DateTime(2026, 9, 5)).nextOnOrAfter(DateTime(2026, 6, 20)),
        DateTime(2026, 9, 5),
      );
    });
  });

  group('statusOn', () {
    final today = DateTime(2026, 6, 20, 9);

    RecurringRule monthly({
      DateTime? next,
      DateTime? end,
      bool active = true,
      bool hasTemplate = true,
    }) => RecurringRule(
      id: 5,
      templateTransactionId: hasTemplate ? 9 : null,
      frequency: RecurrenceFrequency.monthly,
      dayOfMonth: 5,
      startDate: DateTime(2026, 1, 5),
      nextDueDate: next ?? DateTime(2026, 7, 5),
      endDate: end,
      isActive: active,
    );

    test('active when the next entry is ahead', () {
      expect(monthly().statusOn(today), RecurrenceStatus.active);
    });

    test('active, not overdue, when the next entry is today', () {
      expect(
        monthly(next: DateTime(2026, 6, 20)).statusOn(today),
        RecurrenceStatus.active,
      );
    });

    test('overdue when an active rule was left due before today', () {
      expect(
        monthly(next: DateTime(2026, 6, 5)).statusOn(today),
        RecurrenceStatus.overdue,
      );
    });

    test('paused when stopped with entries still to come', () {
      expect(monthly(active: false).statusOn(today), RecurrenceStatus.paused);
      // Paused long enough to have missed some: still paused, not overdue.
      expect(
        monthly(next: DateTime(2026, 2, 5), active: false).statusOn(today),
        RecurrenceStatus.paused,
      );
    });

    test('ended when the next entry is past the end, active or not', () {
      final end = DateTime(2026, 6, 30);
      expect(
        monthly(end: end, active: false).statusOn(today),
        RecurrenceStatus.ended,
      );
      expect(monthly(end: end).statusOn(today), RecurrenceStatus.ended);
    });

    test('no template outranks everything (E-36)', () {
      expect(
        monthly(
          hasTemplate: false,
          active: false,
          end: DateTime(2026, 6, 30),
        ).statusOn(today),
        RecurrenceStatus.noTemplate,
      );
    });
  });

  group('entryOn', () {
    test('copies what the money was from the template, and dates it', () {
      final start = DateTime(2026, 1, 5);
      final template = Transaction(
        id: 9,
        accountId: 2,
        categoryId: 7,
        amountCents: 4500000,
        type: TransactionType.expense,
        date: start,
        time: '09:00',
        note: 'Rent',
        receiptScanId: 3,
        receiptImagePath: '/receipts/3.jpg',
      );
      final r = rule(RecurrenceFrequency.monthly, start: start, dayOfMonth: 5);

      final entry = r.entryOn(DateTime(2026, 2, 5, 13), template);

      expect(
        entry,
        Transaction(
          accountId: 2,
          categoryId: 7,
          amountCents: 4500000,
          type: TransactionType.expense,
          date: DateTime(2026, 2, 5),
          time: '09:00',
          note: 'Rent',
          recurringRuleId: 5,
          isRecurring: true,
        ),
      );
    });
  });
}
