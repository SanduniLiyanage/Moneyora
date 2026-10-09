import 'package:equatable/equatable.dart';

/// Which way a debt runs. FR-DBT-001.
enum DebtDirection {
  /// Someone owes the user: a loan to a friend, a bill the user paid for.
  owedToMe('owed_to_me'),

  /// The user owes someone.
  iOwe('i_owe');

  const DebtDirection(this.storageValue);

  /// The `debts.direction` value.
  final String storageValue;

  /// The direction stored as [value].
  static DebtDirection fromStorage(String value) =>
      values.firstWhere((d) => d.storageValue == value);
}

/// Money owed, to the user or by them, until it is paid. FR-DBT-001, E-42.
///
/// Not a transaction and not tied to an account: a debt is a promise, and
/// when it is kept the money moves through whatever account it moves
/// through, recorded there as any income or expense is.
class Debt extends Equatable {
  /// Creates a debt.
  const Debt({
    required this.direction,
    required this.person,
    required this.amountCents,
    required this.incurredOn,
    this.id,
    this.note,
    this.dueOn,
    this.paidOn,
  });

  /// Row id, null before it is saved.
  final int? id;

  /// Which way it runs.
  final DebtDirection direction;

  /// Who: the one owing, or the one owed.
  final String person;

  /// How much, in minor units. Always positive; [direction] is the sign.
  final int amountCents;

  /// What it was for, if the user said.
  final String? note;

  /// The day it began.
  final DateTime incurredOn;

  /// The day it should be paid by, if there is one.
  final DateTime? dueOn;

  /// The day it was paid, or null while it is still open. FR-DBT-003.
  final DateTime? paidOn;

  /// True until it is paid.
  bool get isOpen => paidOn == null;

  /// True when it is still open after its due day. [today] is the clock,
  /// passed in so a test can state the day.
  bool isOverdue(DateTime today) {
    final due = dueOn;
    if (due == null || !isOpen) return false;
    return DateTime(
      today.year,
      today.month,
      today.day,
    ).isAfter(DateTime(due.year, due.month, due.day));
  }

  /// This debt, paid on [day], or open again when [day] is null.
  Debt withPaidOn(DateTime? day) => Debt(
    id: id,
    direction: direction,
    person: person,
    amountCents: amountCents,
    note: note,
    incurredOn: incurredOn,
    dueOn: dueOn,
    paidOn: day,
  );

  @override
  List<Object?> get props => [
    id,
    direction,
    person,
    amountCents,
    note,
    incurredOn,
    dueOn,
    paidOn,
  ];
}
