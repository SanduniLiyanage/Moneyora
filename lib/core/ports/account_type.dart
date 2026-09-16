/// What kind of place money sits in. FR-ACC-001.
///
/// The distinction is presentational — every type behaves identically in the
/// ledger — but it is what lets a person recognise their own accounts at a
/// glance, and later lets the plan generator treat a credit card differently
/// from cash if it ever needs to.
///
/// Lives in `core/ports/` rather than the accounts feature because
/// [AccountOption] carries it out to other features: the receipt scanner
/// reads `MASTER CARD` off a receipt and needs to know which of the user's
/// accounts is a card (FR-RCP-008). `features/accounts/` re-exports it from
/// its `Account` entity, so inside that feature nothing changed.
enum AccountType {
  /// Notes and coins.
  cash('cash'),

  /// A current or savings account.
  bank('bank'),

  /// Money owed rather than held. Its balance is normally negative.
  creditCard('credit_card'),

  /// eZ Cash, FriMi, a mobile wallet.
  digitalWallet('digital_wallet'),

  /// Held in a cryptocurrency.
  crypto('crypto'),

  /// Anything the list above does not describe.
  custom('custom');

  const AccountType(this.storageValue);

  /// The exact string the schema's `CHECK` constraint permits.
  ///
  /// Written out rather than derived from `name`, because `creditCard.name` is
  /// `creditCard` and the column accepts only `credit_card`. The same trap as
  /// `TransferDirection.incoming` against `'in'` (E-16), and it is worth
  /// spelling out twice rather than discovering twice.
  final String storageValue;
}
