import 'package:equatable/equatable.dart';

import '../../../../core/ports/conversion_table.dart';
import 'account.dart';

/// The one balance figure above the account list, and what it leaves out.
/// FR-ACC-003, FR-ACC-005.
///
/// Adding balances into a single number is not simply summing the column,
/// for two unrelated reasons that must not be conflated:
///
/// * **The user's choice.** FR-ACC-002's Include-in-Total toggle exists so a
///   shared household account, or one held for someone else, can be visible
///   without counting as your money.
/// * **A rate the user has not entered.** FR-ACC-005 converts every account
///   into the base currency at the user's own rates (E-34). An account whose
///   currency has no rate *to the base* cannot be honestly added, so it is
///   left out *and said to be left out* — E-25's interim behaviour, kept as
///   the fallback — rather than converted at an invented rate or added as
///   though a dollar were a rupee.
///
/// Keeping the two apart is the point of this class. An account the user
/// excluded is not evidence of a missing rate, so it never appears in
/// [unconvertedCount] and never produces a message about rates.
///
/// Pure Dart over a list and a table already in hand, so it is an entity
/// with a factory rather than a use case: there is no repository to call.
class AccountTotals extends Equatable {
  /// Creates a total.
  const AccountTotals({
    required this.baseCurrency,
    required this.totalCents,
    required this.unconvertedCount,
  });

  /// Adds up [accounts] in [table]'s base currency, leaving out what cannot
  /// honestly be added.
  factory AccountTotals.from(
    Iterable<Account> accounts,
    ConversionTable table,
  ) {
    var total = 0;
    var unconverted = 0;

    for (final account in accounts) {
      // Archived accounts are not part of the picture at all (FR-ACC-004),
      // and one the user excluded is their decision rather than a limitation
      // of the app — so neither reaches the currency question below.
      if (account.isArchived || !account.includeInTotal) continue;

      final converted = table.toBase(
        account.currentBalanceCents,
        account.currency,
      );
      if (converted == null) {
        unconverted++;
      } else {
        total += converted;
      }
    }

    return AccountTotals(
      baseCurrency: table.baseCurrency,
      totalCents: total,
      unconvertedCount: unconverted,
    );
  }

  /// The currency [totalCents] is expressed in: the user's base currency
  /// (FR-SET-003).
  final String baseCurrency;

  /// The sum, in minor units of [baseCurrency], of every account counted —
  /// each converted at the user's rate where one was needed.
  ///
  /// Signed: a credit card pulls the total down, which is what owing money
  /// does, in whatever currency it is owed.
  final int totalCents;

  /// How many accounts were left out because their currency has no rate to
  /// [baseCurrency].
  ///
  /// Counted, not summed — there is nothing meaningful to add them to. It
  /// exists so the screen can say what it left out and what would include
  /// it, which is the difference between a stated limit and a wrong number.
  final int unconvertedCount;

  /// Whether anything was left out for want of a rate (E-34).
  bool get hasUnconverted => unconvertedCount > 0;

  @override
  List<Object?> get props => [baseCurrency, totalCents, unconvertedCount];
}
