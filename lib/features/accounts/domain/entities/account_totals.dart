import 'package:equatable/equatable.dart';

import 'account.dart';

/// The one balance figure above the account list, and what it leaves out.
///
/// FR-ACC-003 asks for accounts shown "with current balances". Adding those
/// balances into a single number is not simply summing the column, for two
/// unrelated reasons that must not be conflated:
///
/// * **The user's choice.** FR-ACC-002's Include-in-Total toggle exists so a
///   shared household account, or one held for someone else, can be visible
///   without counting as your money.
/// * **The app's limit.** FR-ACC-005 — multi-currency conversion — is deferred
///   to Sprint 7 by [E-25](../../../../../docs/SPEC_ERRATA.md), so there is no
///   honest way to add USD to LKR yet. Foreign-currency accounts are left out
///   *and said to be left out*, rather than converted at an invented rate or
///   added as though a dollar were a rupee.
///
/// Keeping the two apart is the point of this class. An account the user
/// excluded is not evidence of a missing feature, so it never appears in
/// [excludedForeignCount] and never produces a message about conversion.
///
/// Pure Dart over a list already in hand, so it is an entity with a factory
/// rather than a use case: there is no repository to call.
class AccountTotals extends Equatable {
  /// Creates a total.
  const AccountTotals({
    required this.baseCurrency,
    required this.totalCents,
    required this.excludedForeignCount,
  });

  /// Adds up [accounts], leaving out what cannot honestly be added.
  factory AccountTotals.from(
    Iterable<Account> accounts, {
    String baseCurrency = defaultBaseCurrency,
  }) {
    final base = baseCurrency.toUpperCase();
    var total = 0;
    var foreign = 0;

    for (final account in accounts) {
      // Archived accounts are not part of the picture at all (FR-ACC-004),
      // and one the user excluded is their decision rather than a limitation
      // of the app — so neither reaches the currency question below.
      if (account.isArchived || !account.includeInTotal) continue;

      if (account.currency.toUpperCase() == base) {
        total += account.currentBalanceCents;
      } else {
        foreign++;
      }
    }

    return AccountTotals(
      baseCurrency: base,
      totalCents: total,
      excludedForeignCount: foreign,
    );
  }

  /// The currency totals are expressed in until FR-ACC-005 makes it a setting.
  ///
  /// LKR because it is [Account]'s default and what `default_seed.dart`
  /// creates, so on every install that exists today the total covers
  /// everything. E-25 records this as interim: when conversion lands, this
  /// constant is replaced by the user's chosen base rather than removed.
  static const String defaultBaseCurrency = 'LKR';

  /// The currency [totalCents] is expressed in.
  final String baseCurrency;

  /// The sum, in minor units, of every account counted.
  ///
  /// Signed: a credit card in [baseCurrency] pulls the total down, which is
  /// what owing money does.
  final int totalCents;

  /// How many accounts were left out because they hold another currency.
  ///
  /// Counted, not summed — there is nothing meaningful to add them to. It
  /// exists so the screen can say what it left out, which is the difference
  /// between a stated limit and a wrong number.
  final int excludedForeignCount;

  /// Whether anything was left out for want of conversion (E-25).
  bool get hasExcludedForeign => excludedForeignCount > 0;

  @override
  List<Object?> get props => [baseCurrency, totalCents, excludedForeignCount];
}
