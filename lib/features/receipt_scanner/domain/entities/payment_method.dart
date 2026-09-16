import '../../../../core/ports/account_reader.dart';

/// How a receipt says it was paid. FR-RCP-005, FR-RCP-008.
///
/// Read off the tender line — `CASH 3,000.00`, `MASTER CARD 2790.00`,
/// `PAID BY VISA` — so the review screen can open with the account that
/// matches rather than the first one in the list. Two values, not a
/// card brand: the app has no notion of which card is a Visa, only which
/// accounts are cards.
enum PaymentMethod {
  /// Notes and coins.
  cash,

  /// A debit or credit card.
  card;

  /// The account types this method is paid from, most likely first: a
  /// card payment is a credit card before a bank account, because the
  /// bank account is what a debit card draws on and the credit card is
  /// the one a person has to remember to settle.
  List<AccountType> get accountTypes => switch (this) {
    cash => const [AccountType.cash],
    card => const [AccountType.creditCard, AccountType.bank],
  };

  /// The first of [accounts], in [accountTypes] order, that this method
  /// would be paid from — or null when none is of a matching type. The
  /// list's own order breaks ties within a type, so the user's first card
  /// is the card.
  int? defaultAccount(List<AccountOption> accounts) {
    for (final type in accountTypes) {
      for (final account in accounts) {
        if (account.type == type) return account.id;
      }
    }
    return null;
  }
}
