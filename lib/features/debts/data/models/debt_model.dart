/// Persistence mapping for [Debt]. E-42.
///
/// The shape `account_model.dart` uses: a model that is an entity, with the
/// row's bookkeeping beside it and [DebtModel.toEntity] to convert at the
/// repository boundary, because `Equatable` compares `runtimeType`.
library;

import '../../../../core/utils/date_utils.dart';
import '../../domain/entities/debt.dart';

/// A [Debt] that can be written to and read from `debts`.
class DebtModel extends Debt {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const DebtModel({
    required super.direction,
    required super.person,
    required super.amountCents,
    required super.incurredOn,
    super.id,
    super.note,
    super.dueOn,
    super.paidOn,
  });

  /// Wraps an entity so it can be written.
  factory DebtModel.fromEntity(Debt debt) => DebtModel(
    id: debt.id,
    direction: debt.direction,
    person: debt.person,
    amountCents: debt.amountCents,
    note: debt.note,
    incurredOn: debt.incurredOn,
    dueOn: debt.dueOn,
    paidOn: debt.paidOn,
  );

  /// Rebuilds a model from a `debts` row.
  factory DebtModel.fromMap(Map<String, Object?> map) => DebtModel(
    id: map['id']! as int,
    direction: DebtDirection.fromStorage(map['direction']! as String),
    person: map['person']! as String,
    amountCents: map['amount_cents']! as int,
    note: map['note'] as String?,
    incurredOn: decodeIsoDay(map['incurred_on']! as String),
    dueOn: switch (map['due_on']) {
      final String day => decodeIsoDay(day),
      _ => null,
    },
    paidOn: switch (map['paid_on']) {
      final String day => decodeIsoDay(day),
      _ => null,
    },
  );

  /// The columns a write sets, `created_at` aside: an update leaves it be.
  Map<String, Object?> toMap({required DateTime now}) => <String, Object?>{
    'direction': direction.storageValue,
    'person': person,
    'amount_cents': amountCents,
    'note': note,
    'incurred_on': encodeIsoDay(incurredOn),
    'due_on': switch (dueOn) {
      final day? => encodeIsoDay(day),
      null => null,
    },
    'paid_on': switch (paidOn) {
      final day? => encodeIsoDay(day),
      null => null,
    },
    'updated_at': now.toUtc().toIso8601String(),
  };

  /// A plain entity, safe to hand to the domain layer.
  Debt toEntity() => Debt(
    id: id,
    direction: direction,
    person: person,
    amountCents: amountCents,
    note: note,
    incurredOn: incurredOn,
    dueOn: dueOn,
    paidOn: paidOn,
  );
}
