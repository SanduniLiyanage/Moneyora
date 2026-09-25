/// Persistence mapping for [RecurringRule]. FR-EXP-008, FR-INC-004.
///
/// Maps to `recurring_rules` as `v1_initial.dart` built it (E-03,
/// Amendment A): `template_tx_id`, the frequency strings the CHECK accepts,
/// `day_of_week` numbered from Sunday at zero, and dates as `YYYY-MM-DD`.
/// The stored strings live here, not on the enum, for the reason
/// `TransactionModel` gives: `RecurrenceFrequency.customDays.name` is not
/// what the column holds.
library;

import '../../../../core/utils/date_utils.dart';
import '../../domain/entities/recurring_rule.dart';

/// A [RecurringRule] that can be written to and read from SQLite.
class RecurringRuleModel extends RecurringRule {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const RecurringRuleModel({
    required super.frequency,
    required super.startDate,
    required super.nextDueDate,
    super.id,
    super.templateTransactionId,
    super.intervalDays,
    super.dayOfWeek,
    super.dayOfMonth,
    super.endDate,
    super.lastCreatedAt,
    super.isActive,
  });

  /// Wraps an entity so it can be written.
  factory RecurringRuleModel.fromEntity(RecurringRule rule) =>
      RecurringRuleModel(
        id: rule.id,
        templateTransactionId: rule.templateTransactionId,
        frequency: rule.frequency,
        intervalDays: rule.intervalDays,
        dayOfWeek: rule.dayOfWeek,
        dayOfMonth: rule.dayOfMonth,
        startDate: rule.startDate,
        endDate: rule.endDate,
        nextDueDate: rule.nextDueDate,
        lastCreatedAt: rule.lastCreatedAt,
        isActive: rule.isActive,
      );

  /// Rebuilds a model from a `recurring_rules` row.
  factory RecurringRuleModel.fromMap(Map<String, Object?> map) {
    final dayOfWeek = map['day_of_week'] as int?;
    final endDate = map['end_date'] as String?;
    final lastCreatedAt = map['last_created_at'] as String?;
    return RecurringRuleModel(
      id: map['id'] as int?,
      templateTransactionId: map['template_tx_id'] as int?,
      frequency: decodeFrequency(map['frequency']! as String),
      intervalDays: map['interval_days'] as int?,
      dayOfWeek: dayOfWeek == null ? null : decodeWeekdayColumn(dayOfWeek),
      dayOfMonth: map['day_of_month'] as int?,
      startDate: decodeIsoDay(map['start_date']! as String),
      endDate: endDate == null ? null : decodeIsoDay(endDate),
      nextDueDate: decodeIsoDay(map['next_due_date']! as String),
      lastCreatedAt: lastCreatedAt == null
          ? null
          : DateTime.parse(lastCreatedAt),
      isActive: map['is_active'] == 1,
    );
  }

  /// The row to write to `recurring_rules`. `id` is omitted when null so
  /// SQLite assigns one.
  Map<String, Object?> toMap() {
    final dayOfWeek = this.dayOfWeek;
    final endDate = this.endDate;
    return <String, Object?>{
      if (id != null) 'id': id,
      'template_tx_id': templateTransactionId,
      'frequency': encodeFrequency(frequency),
      'interval_days': intervalDays,
      'day_of_week': dayOfWeek == null ? null : encodeWeekdayColumn(dayOfWeek),
      'day_of_month': dayOfMonth,
      'start_date': encodeIsoDay(startDate),
      'end_date': endDate == null ? null : encodeIsoDay(endDate),
      'next_due_date': encodeIsoDay(nextDueDate),
      'last_created_at': lastCreatedAt?.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  /// A plain entity, safe to hand to the domain layer. See
  /// `TransactionModel.toEntity` for why this is not cosmetic.
  RecurringRule toEntity() => RecurringRule(
    id: id,
    templateTransactionId: templateTransactionId,
    frequency: frequency,
    intervalDays: intervalDays,
    dayOfWeek: dayOfWeek,
    dayOfMonth: dayOfMonth,
    startDate: startDate,
    endDate: endDate,
    nextDueDate: nextDueDate,
    lastCreatedAt: lastCreatedAt,
    isActive: isActive,
  );

  /// [frequency] as the column's CHECK spells it.
  static String encodeFrequency(RecurrenceFrequency frequency) =>
      switch (frequency) {
        RecurrenceFrequency.daily => 'daily',
        RecurrenceFrequency.weekly => 'weekly',
        RecurrenceFrequency.monthly => 'monthly',
        RecurrenceFrequency.yearly => 'yearly',
        RecurrenceFrequency.customDays => 'custom_days',
      };

  /// The inverse of [encodeFrequency].
  static RecurrenceFrequency decodeFrequency(String value) => switch (value) {
    'daily' => RecurrenceFrequency.daily,
    'weekly' => RecurrenceFrequency.weekly,
    'monthly' => RecurrenceFrequency.monthly,
    'yearly' => RecurrenceFrequency.yearly,
    'custom_days' => RecurrenceFrequency.customDays,
    _ => throw FormatException('Unknown recurrence frequency', value),
  };
}
