/// What a row shows as an account's money. FR-ACC-003, FR-ACC-009, E-46.
library;

import 'dart:math' as math;

import '../ports/account_type.dart';
import 'currency_utils.dart';

/// An account's money as a list or a picker shows it: its balance, or, for
/// a credit card with a limit, what is left to spend.
///
/// A card's balance is what is owed on it, at or below zero, so a card with
/// a limit and nothing spent read Rs0.00 everywhere but Credit cards, and a
/// tester reported the limit lost (E-46). Where a person expects a balance,
/// a card with a limit shows the limit less what is owed, with what is
/// owed beside it: the Credit cards screen's arithmetic (E-43), in which a
/// card in credit owes nothing. A card without a limit has nothing to take
/// what is owed from, so it shows its balance, as every other account does.
///
/// Display only. The stored balance is unchanged, and the total across
/// accounts adds balances, never available credit: credit is not money the
/// user has.
class AccountFigure {
  const AccountFigure._({required this.cents, this.owedCents});

  /// The figure for an account of [type] holding [balanceCents], with
  /// [creditLimitCents] when it is a card whose limit was entered.
  factory AccountFigure.of({
    required AccountType type,
    required int balanceCents,
    int? creditLimitCents,
  }) {
    final limit = creditLimitCents;
    if (type != AccountType.creditCard || limit == null) {
      return AccountFigure._(cents: balanceCents);
    }
    final owed = math.max(0, -balanceCents);
    return AccountFigure._(cents: limit - owed, owedCents: owed);
  }

  /// The balance, or what is left to spend on a card with a limit. Below
  /// zero for an account overdrawn, or a card over its limit.
  final int cents;

  /// What is owed on a card with a limit; null for any other account.
  final int? owedCents;

  /// True when [cents] is credit left to spend rather than a balance.
  bool get isAvailableCredit => owedCents != null;

  /// [cents] as an amount, `Rs37,500.00`, signed as a balance is.
  String amount(CurrencyFormat currency) =>
      formatCents(cents, currency: currency);

  /// What the amount is, for the line under it: `Available · owed
  /// Rs12,500.00`, or `Over the limit · …`. Null for a balance, which
  /// needs no saying.
  String? caption(CurrencyFormat currency) => switch (_owed(currency)) {
    final owed? => '${cents < 0 ? 'Over the limit' : 'Available'} · $owed',
    null => null,
  };

  /// The amount and what it is, on one line: `Rs37,500.00 available ·
  /// owed Rs12,500.00`. A balance alone for any other account.
  String summary(CurrencyFormat currency) => switch (_owed(currency)) {
    final owed? => '${label(currency)} · $owed',
    null => amount(currency),
  };

  /// The amount with what it is, and no more: `Rs37,500.00 available`, or
  /// `Rs2,000.00 over the limit`. A balance alone for any other account.
  String label(CurrencyFormat currency) => switch (owedCents) {
    null => amount(currency),
    _ when cents < 0 =>
      '${formatCents(-cents, currency: currency)} over the limit',
    _ => '${amount(currency)} available',
  };

  String? _owed(CurrencyFormat currency) => switch (owedCents) {
    null => null,
    0 => 'nothing owed',
    final owed => 'owed ${formatCents(owed, currency: currency)}',
  };
}
