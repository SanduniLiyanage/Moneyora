import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/transaction_repository.dart';

/// What to move, and between which accounts. Input to [MakeTransfer].
class TransferParams extends Equatable {
  /// Creates the parameters for a transfer.
  const TransferParams({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountCents,
    required this.date,
    this.note,
    this.fromCurrency = defaultCurrency,
    this.toCurrency = defaultCurrency,
  });

  /// What both sides are assumed to hold unless the caller says otherwise.
  ///
  /// LKR, matching `Account.currency`'s default and what `default_seed.dart`
  /// creates. Defaulted rather than required so every existing caller and test
  /// keeps meaning what it meant: a transfer between two rupee accounts.
  static const String defaultCurrency = 'LKR';

  /// Where the money leaves.
  final int fromAccountId;

  /// Where it arrives.
  final int toAccountId;

  /// How much, in minor units. Positive; direction comes from the two account
  /// fields, never from the sign.
  final int amountCents;

  /// The day it happened.
  final DateTime date;

  /// Free text shown on both halves.
  final String? note;

  /// The currency the source account holds.
  final String fromCurrency;

  /// The currency the destination account holds.
  final String toCurrency;

  @override
  List<Object?> get props => [
    fromAccountId,
    toAccountId,
    amountCents,
    date,
    note,
    fromCurrency,
    toCurrency,
  ];
}

/// Moves money between two of the user's own accounts. FR-TRF-002.
///
/// An **account** is where money sits — Cash, Payment card, Bank. A transfer
/// moves an amount from one to another: the source falls, the destination
/// rises, and it is neither income nor spending. Withdrawing Rs 8,000 from a
/// card and holding it as cash is one transfer, not an expense and an income.
///
/// This is the sibling of `AddTransaction`, and it exists for the same reason:
/// the schema already refuses a transfer to the account it came from, but a
/// `CHECK` constraint failing produces a SQLite error. This produces a message
/// a screen can show a person.
///
/// Transfers carry no category (E-17) and no split, so neither appears here.
class MakeTransfer implements UseCase<int, TransferParams> {
  /// Creates the use case.
  const MakeTransfer(this._repository);

  final TransactionRepository _repository;

  @override
  Future<Either<Failure, int>> call(TransferParams params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    return _repository.transfer(
      fromAccountId: params.fromAccountId,
      toAccountId: params.toAccountId,
      amountCents: params.amountCents,
      date: params.date,
      note: params.note,
    );
  }

  /// Returns the reason [params] is invalid, or null if it is fine.
  ///
  /// Public and static so a transfer screen can check as the user types,
  /// rather than discovering the problem only when Save fails.
  static ValidationFailure? validate(TransferParams params) {
    if (params.amountCents <= 0) {
      return const ValidationFailure(
        'Enter an amount greater than zero.',
        field: 'amount',
      );
    }

    if (params.fromAccountId == params.toAccountId) {
      // The schema enforces this too, with CHECK(from_account_id <>
      // to_account_id). That is the last line of defence and produces a
      // constraint error; this produces a sentence.
      return const ValidationFailure(
        'Choose two different accounts — money cannot move to where it '
        'already is.',
        field: 'toAccount',
      );
    }

    if (params.fromCurrency.trim().toUpperCase() !=
        params.toCurrency.trim().toUpperCase()) {
      // E-25's interim rule. FR-TRF-001 permits a transfer between any two
      // active accounts, and FR-ACC-005 — the conversion that would make a
      // cross-currency one meaningful — is deferred to Sprint 7. Until it
      // lands there is no rate to convert at, and moving 100 from a USD
      // account to an LKR one would credit 100 rupees: a number that is
      // wrong by a factor of three hundred and looks entirely plausible.
      //
      // Refusing with a sentence is the honest answer. Delete this rule in
      // the same commit that adds conversion, or the app will keep refusing
      // transfers it has become capable of making.
      return ValidationFailure(
        'Moneyora cannot convert between currencies yet, so a transfer has '
        'to be between two ${params.fromCurrency.trim().toUpperCase()} '
        'accounts.',
        field: 'toAccount',
      );
    }

    if (params.date.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      // A day of slack, matching AddTransaction: a device clock in another
      // time zone is a legitimate reason for a date to look like tomorrow.
      return const ValidationFailure(
        'That date is in the future.',
        field: 'date',
      );
    }

    return null;
  }
}
