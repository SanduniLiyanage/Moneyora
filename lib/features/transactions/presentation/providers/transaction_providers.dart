/// Presentation state for the transactions feature.
///
/// These providers talk to **use cases**, never to a repository or a
/// datasource — that is the rule `scripts/check_architecture.sh` enforces, and
/// the reason the whole slice can be exercised in tests by overriding one
/// provider.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/database/entry_catalog.dart';
import '../../../../core/errors/failures.dart';
import '../../../../injection.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';

/// The categories and accounts the entry screen offers.
final entryCatalogProvider = FutureProvider<EntryCatalog>((ref) async {
  return readEntryCatalog(await ref.watch(databaseProvider.future));
});

/// The transactions matching [filter], kept live.
///
/// A `StreamProvider` rather than a future, so adding a transaction on the
/// entry screen updates the list behind it without either screen knowing the
/// other exists. The stream re-queries on every write; see
/// `TransactionRepositoryImpl.watch` for why it is a signal and not a diff.
final transactionsProvider =
    StreamProvider.family<List<Transaction>, TransactionFilter>((ref, filter) {
      return Stream.fromFuture(ref.watch(watchTransactionsProvider.future))
          .asyncExpand((watchTransactions) => watchTransactions(filter))
          // A `Left` goes down the stream's error channel, so it arrives as
          // `AsyncValue.error` and each screen handles it in the branch its
          // `.when` already has. Unwrapping once here saves every widget from
          // repeating the same fold.
          //
          // `sink.addError` rather than `throw`: a `Failure` is a value, not
          // an exception — `data/` throws and `domain/` returns failures, and
          // ARCHITECTURE.md §3 keeps those two vocabularies apart on purpose.
          .transform(
            StreamTransformer<
              Either<Failure, List<Transaction>>,
              List<Transaction>
            >.fromHandlers(
              handleData: (result, sink) =>
                  result.match(sink.addError, sink.add),
            ),
          );
    });

/// Saves a transaction, exposing the attempt as an [AsyncValue].
///
/// An `AsyncNotifier` rather than local widget state because a save has three
/// outcomes a screen must render — in flight, failed, done — and `AsyncValue`
/// has no "success only" shape to forget about.
class SaveTransactionController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Validates and saves [transaction].
  ///
  /// Routes on whether the transaction has an id: no id means it has never
  /// been written. One method rather than two because the screen is one
  /// screen, and a caller that has to know which to call is a caller that can
  /// pick wrong.
  ///
  /// Returns true when it was written, so the caller can pop the screen. The
  /// failure is left in [state] for the screen to show.
  Future<bool> save(Transaction transaction) async {
    state = const AsyncValue<void>.loading();

    // The two use cases return different Right types — a new id, or unit — and
    // this method cares about neither, only whether it worked.
    final Either<Failure, void> result;
    if (transaction.id == null) {
      final addTransaction = await ref.read(addTransactionProvider.future);
      result = await addTransaction(transaction);
    } else {
      final updateTransaction = await ref.read(
        updateTransactionProvider.future,
      );
      result = await updateTransaction(transaction);
    }

    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        return true;
      },
    );
  }
}

/// Controller for the entry screen's save button.
final saveTransactionControllerProvider =
    AutoDisposeAsyncNotifierProvider<SaveTransactionController, void>(
      SaveTransactionController.new,
    );

/// A human-readable reason a save failed, or null while nothing has gone wrong.
///
/// Failures carry their own message precisely so the UI never has to invent
/// one; this only unwraps it.
String? failureMessage(Object? error) => switch (error) {
  final Failure failure => failure.message,
  null => null,
  _ => 'Something went wrong. Please try again.',
};

/// Transactions deleted on screen but not yet written away. E-23.
///
/// The undo window is here, in presentation, rather than in the datasource,
/// because E-23's resolution is to **defer the write** rather than to delete
/// and re-insert. A re-inserted row takes a new `AUTOINCREMENT` id, which
/// orphans the split parts that cascaded away with it and any receipt link,
/// and would move the balance cache twice in opposite directions.
///
/// So the row is hidden immediately, and `DeleteTransaction` is not called at
/// all until the window closes. If the app dies mid-window nothing was
/// deleted, which is the safe direction to fail when the data is money.
class PendingDeletions extends Notifier<Set<int>> {
  final Map<int, Timer> _timers = {};

  /// How long the user has to change their mind. Matches the snackbar.
  static const Duration window = Duration(seconds: 5);

  @override
  Set<int> build() {
    // Teardown cancels rather than commits, which is exactly what E-23 asks
    // for: "if the app is killed mid-window, nothing was deleted — the safe
    // direction to fail when the data is money."
    //
    // It is also the only thing that can work. This provider outlives every
    // screen, so it is disposed only when the whole container goes, and by
    // then `ref.read` cannot reach the use case any more. An earlier draft
    // tried to flush here and threw "read from a ProviderContainer that was
    // already disposed" — the framework refusing to let a write outlive the
    // app that ordered it.
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const {};
  }

  /// Hides [id] and schedules the write.
  void schedule(int id) {
    state = {...state, id};
    _timers[id] = Timer(window, () => unawaited(_commit(id)));
  }

  /// Puts [id] back, and never writes.
  void undo(int id) {
    _timers.remove(id)?.cancel();
    state = {...state}..remove(id);
  }

  Future<void> _commit(int id) async {
    _timers.remove(id);
    final deleteTransaction = await ref.read(deleteTransactionProvider.future);
    await deleteTransaction(id);
    // Only stop hiding it once the row is actually gone, or the list would
    // show it again for the instant between the write and the next query.
    state = {...state}..remove(id);
  }
}

/// The rows hidden by an undo window that has not closed yet.
final pendingDeletionsProvider = NotifierProvider<PendingDeletions, Set<int>>(
  PendingDeletions.new,
);
