import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/presentation/widgets/recurrence_labels.dart';

void main() {
  RecurringRule rule(
    RecurrenceFrequency frequency, {
    DateTime? start,
    DateTime? next,
    int? intervalDays,
    int? dayOfWeek,
    int? dayOfMonth,
    DateTime? end,
    bool active = true,
    bool hasTemplate = true,
  }) => RecurringRule(
    id: 1,
    templateTransactionId: hasTemplate ? 9 : null,
    frequency: frequency,
    startDate: start ?? DateTime(2026, 1, 5),
    nextDueDate: next ?? DateTime(2026, 7, 5),
    intervalDays: intervalDays,
    dayOfWeek: dayOfWeek,
    dayOfMonth: dayOfMonth,
    endDate: end,
    isActive: active,
  );

  group('describeRecurrence', () {
    test('says each frequency the way a person would', () {
      expect(describeRecurrence(rule(RecurrenceFrequency.daily)), 'Every day');
      expect(
        describeRecurrence(
          rule(RecurrenceFrequency.weekly, dayOfWeek: DateTime.wednesday),
        ),
        'Every Wednesday',
      );
      expect(
        describeRecurrence(
          rule(RecurrenceFrequency.weekly, dayOfWeek: DateTime.sunday),
        ),
        'Every Sunday',
      );
      expect(
        describeRecurrence(rule(RecurrenceFrequency.monthly, dayOfMonth: 22)),
        'Monthly on the 22nd',
      );
      expect(
        describeRecurrence(
          rule(RecurrenceFrequency.yearly, start: DateTime(2024, 2, 29)),
        ),
        'Yearly on February 29',
      );
      expect(
        describeRecurrence(
          rule(RecurrenceFrequency.customDays, intervalDays: 10),
        ),
        'Every 10 days',
      );
    });

    test('a weekly or monthly rule stored without its day reads the start', () {
      expect(
        describeRecurrence(
          rule(RecurrenceFrequency.weekly, start: DateTime(2026, 3, 4)),
        ),
        'Every Wednesday',
      );
      expect(
        describeRecurrence(
          rule(RecurrenceFrequency.monthly, start: DateTime(2026, 3, 3)),
        ),
        'Monthly on the 3rd',
      );
    });
  });

  group('describeStatus', () {
    final today = DateTime(2026, 6, 20);

    test('names the next date for a rule that posts', () {
      expect(
        describeStatus(rule(RecurrenceFrequency.daily), today),
        'Next on Jul 5, 2026',
      );
    });

    test('says an overdue rule will be tried again', () {
      expect(
        describeStatus(
          rule(RecurrenceFrequency.daily, next: DateTime(2026, 6, 5)),
          today,
        ),
        'Overdue since Jun 5, 2026. It will try again next time the app '
        'opens.',
      );
    });

    test('paused, ended and no template each have their word', () {
      expect(
        describeStatus(rule(RecurrenceFrequency.daily, active: false), today),
        'Paused',
      );
      expect(
        describeStatus(
          rule(RecurrenceFrequency.daily, end: DateTime(2026, 6, 30)),
          today,
        ),
        'Ended',
      );
      expect(
        describeStatus(
          rule(RecurrenceFrequency.daily, hasTemplate: false),
          today,
        ),
        'Stopped: its first entry was deleted',
      );
    });
  });

  test('ordinal handles the teens', () {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 28].map(ordinal), [
      '1st',
      '2nd',
      '3rd',
      '4th',
      '11th',
      '12th',
      '13th',
      '21st',
      '22nd',
      '23rd',
      '28th',
    ]);
  });

  test('every frequency has a chip label', () {
    expect(RecurrenceFrequency.values.map(frequencyLabel), [
      'Daily',
      'Weekly',
      'Monthly',
      'Yearly',
      'Every N days',
    ]);
  });
}
