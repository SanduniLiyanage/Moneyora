import 'package:equatable/equatable.dart';

/// What kind of place money sits in. FR-ACC-001.
///
/// The distinction is presentational — every type behaves identically in the
/// ledger — but it is what lets a person recognise their own accounts at a
/// glance, and later lets the plan generator treat a credit card differently
/// from cash if it ever needs to.
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

/// A place money sits: Cash, a payment card, a bank account. FR-ACC-001.
///
/// An **account** is *where* money is. A **category** is *what* it was spent
/// on. Transfers move between accounts and never touch a category (E-17), and
/// keeping the two words apart is the difference between a schema that models
/// personal finance and one that models a shopping list.
class Account extends Equatable {
  /// Creates an account.
  const Account({
    required this.name,
    required this.icon,
    required this.initialBalanceDate,
    this.id,
    this.type = AccountType.cash,
    this.currency = 'LKR',
    this.initialBalanceCents = 0,
    this.currentBalanceCents = 0,
    this.includeInTotal = true,
    this.isArchived = false,
  });

  /// Row id, null before it is saved.
  final int? id;

  /// What the user calls it.
  final String name;

  /// Icon key, e.g. `wallet`.
  final String icon;

  /// Which kind of account this is.
  final AccountType type;

  /// ISO 4217 code. LKR unless the user says otherwise.
  final String currency;

  /// What was in it on [initialBalanceDate], in minor units.
  ///
  /// Signed, unlike a transaction amount: a credit card can legitimately open
  /// with a negative balance, because the money is owed rather than held.
  final int initialBalanceCents;

  /// The balance as last computed, in minor units.
  ///
  /// **A cache, not a source of truth** (E-18). It is maintained inside the
  /// same database transaction as every row that moves it, and
  /// `RecomputeAccountBalance` re-derives it from history. Nothing should
  /// treat this as authoritative without knowing it can be reconciled.
  final int currentBalanceCents;

  /// The day [initialBalanceCents] was true.
  ///
  /// Transactions before this date are still counted; the opening balance is
  /// a starting point, not a floor. Recording it lets a user who joins
  /// mid-year enter history without their balance going wrong.
  final DateTime initialBalanceDate;

  /// Whether this account counts towards the overall net worth. FR-ACC-002.
  ///
  /// A shared household account, or one held for someone else, is real money
  /// that is not *your* money.
  final bool includeInTotal;

  /// Archived accounts are hidden but keep their transactions. FR-ACC-004.
  ///
  /// The alternative — deleting — would take the history with it and silently
  /// change every past total the user has already seen. Deletion is therefore
  /// confined to an account with no transactions at all (FR-ACC-007, E-25).
  final bool isArchived;

  /// A copy with the given fields replaced.
  Account copyWith({
    int? id,
    String? name,
    String? icon,
    AccountType? type,
    String? currency,
    int? initialBalanceCents,
    int? currentBalanceCents,
    DateTime? initialBalanceDate,
    bool? includeInTotal,
    bool? isArchived,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    type: type ?? this.type,
    currency: currency ?? this.currency,
    initialBalanceCents: initialBalanceCents ?? this.initialBalanceCents,
    currentBalanceCents: currentBalanceCents ?? this.currentBalanceCents,
    initialBalanceDate: initialBalanceDate ?? this.initialBalanceDate,
    includeInTotal: includeInTotal ?? this.includeInTotal,
    isArchived: isArchived ?? this.isArchived,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    icon,
    type,
    currency,
    initialBalanceCents,
    currentBalanceCents,
    initialBalanceDate,
    includeInTotal,
    isArchived,
  ];
}
