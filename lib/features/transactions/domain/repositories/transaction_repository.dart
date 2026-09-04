import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/transaction.dart';

/// What the app can do with transactions.
///
/// The **contract**, declared in `domain/` and implemented in `data/`. That
/// direction is the whole point of the architecture: the use cases depend on
/// this interface, not on sqflite, so they are testable with a fake and the
/// storage engine could change without touching a line of business logic.
///
/// Every method returns `Either<Failure, T>` — never throws. Exceptions are
/// thrown in `data/` and converted at the repository boundary, so nothing
/// above `data/` needs a `try`/`catch` (see `ARCHITECTURE.md` §3).
abstract interface class TransactionRepository {
  /// Saves a new transaction, returning its assigned id.
  ///
  /// Splits, when present, are written in the same database transaction as the
  /// parent row — a parent without its parts is a transaction whose category
  /// breakdown silently disagrees with its amount.
  Future<Either<Failure, int>> add(Transaction transaction);

  /// Updates an existing transaction.
  Future<Either<Failure, Unit>> update(Transaction transaction);

  /// Deletes by id. Splits cascade with the parent.
  Future<Either<Failure, Unit>> delete(int id);

  /// Reads transactions matching [filter], newest first.
  Future<Either<Failure, List<Transaction>>> list(TransactionFilter filter);

  /// Watches transactions matching [filter].
  ///
  /// A stream rather than repeated reads so the home screen updates when a
  /// transaction is added elsewhere, without every screen polling.
  Stream<Either<Failure, List<Transaction>>> watch(TransactionFilter filter);

  /// Moves money between two accounts as one atomic unit. FR-TRF-002.
  ///
  /// Separate from [add] because a transfer is three rows across two tables —
  /// two `transactions` and one `transfers` — with foreign keys pointing both
  /// ways (E-15). Exposing it as one method is what stops a caller writing
  /// half of one.
  Future<Either<Failure, int>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required DateTime date,
    String? note,
  });
}

/// Which transactions to read. FR-RPT-002, FR-RPT-003, FR-RPT-008.
///
/// Compared by value, which is not decoration. A screen passes one of these as
/// a Riverpod family key, and a family keys on `==`: without value equality
/// every rebuild would look like a *different* filter, tear down the running
/// watch and start a new one. The symptom is a list that flickers and a
/// database queried on every frame — plausible enough to be blamed on the
/// stream rather than on identity.
class TransactionFilter extends Equatable {
  /// Creates a filter. Every field is optional; omitting all of them means
  /// "everything".
  const TransactionFilter({
    this.accountId,
    this.categoryId,
    this.type,
    this.from,
    this.to,
    this.noteContains,
    this.minAmountCents,
    this.maxAmountCents,
    this.excludeTransfers = false,
  });

  /// Analytics filter: income and expense only, no transfers.
  ///
  /// A named constructor because "remember to exclude transfers" is exactly
  /// the kind of instruction that gets forgotten in one query out of twelve,
  /// and the resulting double-count is invisible until someone with two
  /// accounts reads their monthly summary (E-02).
  const TransactionFilter.forAnalytics({
    DateTime? from,
    DateTime? to,
    int? accountId,
    int? categoryId,
  }) : this(
         from: from,
         to: to,
         accountId: accountId,
         categoryId: categoryId,
         excludeTransfers: true,
       );

  /// Restrict to one account.
  final int? accountId;

  /// Restrict to one category.
  final int? categoryId;

  /// Restrict to one type.
  final TransactionType? type;

  /// Inclusive lower bound on date.
  final DateTime? from;

  /// Inclusive upper bound on date.
  final DateTime? to;

  /// Case-insensitive substring of the note. FR-RPT-008.
  final String? noteContains;

  /// Inclusive lower bound on amount, in minor units.
  final int? minAmountCents;

  /// Inclusive upper bound on amount, in minor units.
  final int? maxAmountCents;

  /// Drop transfers entirely. Set by [TransactionFilter.forAnalytics].
  final bool excludeTransfers;

  @override
  List<Object?> get props => [
    accountId,
    categoryId,
    type,
    from,
    to,
    noteContains,
    minAmountCents,
    maxAmountCents,
    excludeTransfers,
  ];
}
