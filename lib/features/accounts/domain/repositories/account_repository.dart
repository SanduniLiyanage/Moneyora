import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/account.dart';

/// What the app can do with accounts. FR-ACC-001 to FR-ACC-005.
///
/// Declared here and implemented in `data/`, so the use cases above it depend
/// on this interface rather than on sqflite. Every method returns
/// `Either<Failure, T>` and none throws.
abstract interface class AccountRepository {
  /// Saves a new account, returning its assigned id.
  Future<Either<Failure, int>> add(Account account);

  /// Updates an existing account.
  ///
  /// Deliberately cannot change [Account.currentBalanceCents]: that column is
  /// a cache maintained by the writes that move it (E-18), and letting an
  /// edit form set it directly would put the cache and the history into a
  /// disagreement nothing could detect.
  Future<Either<Failure, Unit>> update(Account account);

  /// Hides an account without touching its transactions. FR-ACC-005.
  Future<Either<Failure, Unit>> setArchived(int id, {required bool archived});

  /// Permanently removes an account.
  ///
  /// Only safe when nothing references it. The repository reports how many
  /// transactions would be orphaned rather than deciding what to do about
  /// them — that judgement belongs in a use case.
  Future<Either<Failure, Unit>> delete(int id);

  /// How many transactions reference [id], including both halves of any
  /// transfer that touches it.
  Future<Either<Failure, int>> transactionCount(int id);

  /// Reads accounts, archived ones excluded unless asked for.
  Future<Either<Failure, List<Account>>> list({bool includeArchived = false});

  /// Watches accounts, so a balance on screen follows the transactions that
  /// change it without the screen knowing they happened.
  Stream<Either<Failure, List<Account>>> watch({bool includeArchived});

  /// Re-derives the cached balance for [id] from its opening balance plus
  /// every transaction, writes it, and returns it. E-18.
  Future<Either<Failure, int>> recomputeBalance(int id);

  /// Re-derives every account's balance. Used after a restore.
  Future<Either<Failure, Unit>> recomputeAllBalances();
}
