import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// One account money can sit in, seen from outside `features/accounts/`.
/// FR-ACC-001.
///
/// Deliberately narrower than the `Account` entity — no type, no initial
/// balance, no archived flag — because a consumer outside the accounts
/// feature only ever renders a picker, never edits the row.
class AccountOption extends Equatable {
  /// Creates an account option.
  const AccountOption({
    required this.id,
    required this.name,
    required this.balanceCents,
    this.icon = 'wallet',
    this.currency = 'LKR',
  });

  /// Row id, used as `transactions.account_id`.
  final int id;

  /// What the user calls it — Cash, Payment card.
  final String name;

  /// The cached balance (E-18), for display only.
  final int balanceCents;

  /// Icon key from `accounts.icon`. FR-ACC-006.
  final String icon;

  /// ISO 4217 code from `accounts.currency`.
  ///
  /// Carried so a picker can render the balance in the right currency, and so
  /// the transfer screen can refuse to move money between two accounts that do
  /// not share one — E-25's interim rule, until FR-ACC-005 brings conversion.
  final String currency;

  @override
  List<Object?> get props => [id, name, balanceCents, icon, currency];
}

/// Reads the account list from outside `features/accounts/`. E-27.
///
/// `features/transactions/` needs every non-archived account for the entry
/// screen's picker and the transfer screen's two, but may not import
/// `features/accounts/` (`check_architecture.sh` rule 4) — accounts are
/// Sprint 3's own feature, not transactions'. This is the seam between them,
/// the same role `SpendingByCategoryReader` plays between analytics and the
/// Copilot.
///
/// This replaced `core/database/entry_catalog.dart`'s raw-SQL read once the
/// accounts feature slice existed to implement it — see `SPEC_ERRATA.md`
/// E-27.
abstract class AccountReader {
  /// Watches every account that is not archived, kept live.
  Stream<Either<Failure, List<AccountOption>>> watchAll();
}
