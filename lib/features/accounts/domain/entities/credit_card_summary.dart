import 'dart:math';

import 'package:equatable/equatable.dart';

import 'account.dart';

/// A credit card's position today, from its balance and its terms:
/// what is owed, what is left to spend, when the statement and the payment
/// fall, and what owing costs. FR-ACC-009, E-43.
///
/// Each figure that needs a term the user has not entered is null rather
/// than guessed: no limit, no "available"; no due day, no due date; no
/// rate, no interest.
class CreditCardSummary extends Equatable {
  /// Creates a summary. Screens use [CreditCardSummary.of].
  const CreditCardSummary({
    required this.owedCents,
    this.limitCents,
    this.nextStatement,
    this.nextDue,
    this.aprBasisPoints,
  });

  /// [card]'s summary on [today].
  ///
  /// A card's balance goes below zero as it is spent on, so what is owed
  /// is the balance's negative; a card in credit owes nothing.
  factory CreditCardSummary.of(Account card, {required DateTime today}) {
    final terms = card.creditCard;
    return CreditCardSummary(
      owedCents: max(0, -card.currentBalanceCents),
      limitCents: terms.limitCents,
      nextStatement: switch (terms.statementDay) {
        final day? => nextDayOfMonth(day, today),
        null => null,
      },
      nextDue: switch (terms.dueDay) {
        final day? => nextDayOfMonth(day, today),
        null => null,
      },
      aprBasisPoints: terms.aprBasisPoints,
    );
  }

  /// What is owed on the card, in minor units; never below zero.
  final int owedCents;

  /// The most that may be owed, if entered.
  final int? limitCents;

  /// The next day the statement is cut, today included.
  final DateTime? nextStatement;

  /// The next day payment is due, today included.
  final DateTime? nextDue;

  /// The yearly interest rate in hundredths of a percent, if entered.
  final int? aprBasisPoints;

  /// What is left to spend: the limit less what is owed. Negative over the
  /// limit. Null without a limit.
  int? get availableCents => switch (limitCents) {
    final limit? => limit - owedCents,
    null => null,
  };

  /// What is owed as a share of the limit, a whole percentage rounded
  /// down; past 100 over the limit. Null without a limit.
  int? get utilisationPercent => switch (limitCents) {
    final limit? => owedCents * 100 ~/ limit,
    null => null,
  };

  /// Days from [today] to [nextDue]: 0 on the day itself.
  int? daysUntilDue(DateTime today) => switch (nextDue) {
    final due? => DateTime.utc(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays,
    null => null,
  };

  /// A month's interest on what is owed now, if it is not paid in full by
  /// the due day: owed × rate ÷ 12, rounded to the nearest minor unit.
  /// Null without a rate.
  int? get monthlyInterestCents => switch (aprBasisPoints) {
    final apr? => monthlyInterest(owedCents, apr),
    null => null,
  };

  /// [cents] × [aprBasisPoints] ÷ 10,000 ÷ 12, rounded half up, in
  /// integers: a month's interest at a yearly rate.
  static int monthlyInterest(int cents, int aprBasisPoints) =>
      (cents * aprBasisPoints + 60000) ~/ 120000;

  /// The next date on or after [today] that falls on [day] of its month, a
  /// short month taking its last day: the 31st is 30 April and 28 February.
  static DateTime nextDayOfMonth(int day, DateTime today) {
    DateTime inMonth(int year, int month) {
      final last = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, min(day, last));
    }

    final start = DateTime(today.year, today.month, today.day);
    final thisMonth = inMonth(today.year, today.month);
    return thisMonth.isBefore(start)
        ? inMonth(today.year, today.month + 1)
        : thisMonth;
  }

  @override
  List<Object?> get props => [
    owedCents,
    limitCents,
    nextStatement,
    nextDue,
    aprBasisPoints,
  ];
}
