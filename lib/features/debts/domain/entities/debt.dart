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
/// Not a transaction: a debt is a promise. It may name the account its
/// money moved through, and the one it was paid back through (FR-DBT-009,
/// E-47); each such movement moves that account's balance and is never
/// income or spending. Without one, nothing moves, as E-42 had it.
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
    this.isPayment = false,
    this.accountId,
    this.paidAccountId,
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

  /// Whether this is a payment between the user and [person] rather than
  /// money owed: part or all of what is owed, paid back. FR-DBT-008, E-47.
  ///
  /// It runs the other way from what it pays, so it offsets it in the
  /// person's net: Nimal paying back Rs300 of Rs1,000 is a record of
  /// Rs300 running from Nimal to the user, [DebtDirection.iOwe]. It is
  /// money that has moved, so it has no due day, and it closes when the
  /// person is settled up (FR-DBT-007), not with a tick of its own.
  final bool isPayment;

  /// The account the money moved through when the debt began: the one it
  /// left when the user lent it, or arrived in when they borrowed it. Null
  /// when it moved through none the app knows of. FR-DBT-009.
  final int? accountId;

  /// The account it was paid back through, once paid: the one the money
  /// came back into, or left to repay. Null when it went through none, and
  /// always for a payment, which is the money moving. FR-DBT-009.
  final int? paidAccountId;

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

  /// This debt, recorded under [name] instead. FR-DBT-006.
  Debt withPerson(String name) => Debt(
    id: id,
    direction: direction,
    person: name,
    amountCents: amountCents,
    note: note,
    incurredOn: incurredOn,
    dueOn: dueOn,
    paidOn: paidOn,
    isPayment: isPayment,
    accountId: accountId,
    paidAccountId: paidAccountId,
  );

  /// This debt, paid on [day] back through the account [through], or open
  /// again when [day] is null.
  Debt withPaidOn(DateTime? day, {int? through}) => Debt(
    id: id,
    direction: direction,
    person: person,
    amountCents: amountCents,
    note: note,
    incurredOn: incurredOn,
    dueOn: dueOn,
    paidOn: day,
    isPayment: isPayment,
    accountId: accountId,
    paidAccountId: day == null || isPayment ? null : through,
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
    isPayment,
    accountId,
    paidAccountId,
  ];
}
