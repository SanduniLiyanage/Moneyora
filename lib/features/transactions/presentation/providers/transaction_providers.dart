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
  /// Returns true when it was written, so the caller can pop the screen. The
  /// failure is left in [state] for the screen to show.
  Future<bool> save(Transaction transaction) async {
    state = const AsyncValue<void>.loading();

    final addTransaction = await ref.read(addTransactionProvider.future);
    final result = await addTransaction(transaction);

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
