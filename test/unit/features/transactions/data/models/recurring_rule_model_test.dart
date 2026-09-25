import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/transactions/data/models/recurring_rule_model.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';

void main() {
  final full = RecurringRule(
    id: 4,
    templateTransactionId: 9,
    frequency: RecurrenceFrequency.weekly,
    dayOfWeek: DateTime.sunday,
    startDate: DateTime(2026, 3),
    endDate: DateTime(2026, 12, 31),
    nextDueDate: DateTime(2026, 3, 8),
    lastCreatedAt: DateTime(2026, 3, 8, 7, 30),
    isActive: false,
  );

  test('writes every column as the schema stores it', () {
    expect(RecurringRuleModel.fromEntity(full).toMap(), {
      'id': 4,
      'template_tx_id': 9,
      'frequency': 'weekly',
      'interval_days': null,
      'day_of_week': 0,
      'day_of_month': null,
      'start_date': '2026-03-01',
      'end_date': '2026-12-31',
      'next_due_date': '2026-03-08',
      'last_created_at': DateTime(2026, 3, 8, 7, 30).toIso8601String(),
      'is_active': 0,
    });
  });

  test('a full rule survives the round trip, as an entity', () {
    final back = RecurringRuleModel.fromMap(
      RecurringRuleModel.fromEntity(full).toMap(),
    ).toEntity();
    expect(back, full);
    expect(back.runtimeType, RecurringRule);
  });

  test('a sparse rule survives the round trip; a new one has no id', () {
    final sparse = RecurringRule(
      frequency: RecurrenceFrequency.customDays,
      intervalDays: 10,
      startDate: DateTime(2026),
      nextDueDate: DateTime(2026, 1, 11),
    );
    final map = RecurringRuleModel.fromEntity(sparse).toMap();
    expect(map.containsKey('id'), isFalse);
    expect(RecurringRuleModel.fromMap(map).toEntity(), sparse);
  });

  test('every frequency has its own stored string, both ways', () {
    const stored = {
      RecurrenceFrequency.daily: 'daily',
      RecurrenceFrequency.weekly: 'weekly',
      RecurrenceFrequency.monthly: 'monthly',
      RecurrenceFrequency.yearly: 'yearly',
      RecurrenceFrequency.customDays: 'custom_days',
    };
    for (final MapEntry(key: frequency, value: text) in stored.entries) {
      expect(RecurringRuleModel.encodeFrequency(frequency), text);
      expect(RecurringRuleModel.decodeFrequency(text), frequency);
    }
    expect(
      () => RecurringRuleModel.decodeFrequency('custom'),
      throwsFormatException,
    );
  });

  test('Monday to Saturday store as themselves; only Sunday moves', () {
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      final map = RecurringRuleModel.fromEntity(
        RecurringRule(
          frequency: RecurrenceFrequency.weekly,
          dayOfWeek: weekday,
          startDate: DateTime(2026),
          nextDueDate: DateTime(2026),
        ),
      ).toMap();
      expect(map['day_of_week'], weekday == DateTime.sunday ? 0 : weekday);
      expect(RecurringRuleModel.fromMap(map).dayOfWeek, weekday);
    }
  });
}
