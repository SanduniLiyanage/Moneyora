/// Presentation state for the transactions feature.
///
/// These providers talk to **use cases**, never to a repository or a
/// datasource — that is the rule `scripts/check_architecture.sh` enforces, and
/// the reason the whole slice can be exercised in tests by overriding one
/// provider.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/account_reader.dart';
import '../../../../core/ports/category_reader.dart';
import '../../../../core/ports/category_writer.dart';
import '../../../../injection.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/create_recurring_rule.dart';
import '../../domain/usecases/discard_unused_photos.dart';
import '../../domain/usecases/make_transfer.dart';
import 'recurring_catch_up.dart';

/// The categories the entry screen offers, both kinds, kept live.
///
/// Reads through [CategoryReader] rather than `features/categories/`'s own
/// `categoriesProvider` — `features/transactions/` may not import that
/// feature (rule 4) — but the shape is the same live stream, so a category
/// created or edited anywhere shows up here with no invalidation call. E-27
/// retired `core/database/entry_catalog.dart`, the one-shot future this
/// replaced, which is why callers used to invalidate it by hand.
final entryCategoriesProvider = StreamProvider<List<CategoryOption>>((ref) {
  return Stream.fromFuture(ref.watch(categoryReaderProvider.future))
      .asyncExpand((reader) => reader.watchAll())
      .transform(
        StreamTransformer<
          Either<Failure, List<CategoryOption>>,
          List<CategoryOption>
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

/// The non-archived accounts the entry and transfer screens offer, kept live.
///
/// Reads through [AccountReader] for the same reason [entryCategoriesProvider]
/// reads through [CategoryReader]: `features/transactions/` may not import
/// `features/accounts/` (rule 4), and the live stream means a transfer's
/// balance change is already visible with no invalidation call. E-27.
final entryAccountsProvider = StreamProvider<List<AccountOption>>((ref) {
  return Stream.fromFuture(ref.watch(accountReaderProvider.future))
      .asyncExpand((reader) => reader.watchAll())
      .transform(
        StreamTransformer<
          Either<Failure, List<AccountOption>>,
          List<AccountOption>
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
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

  /// Saves [request]'s entry with the rule that repeats it. FR-EXP-008,
  /// FR-INC-004, E-13.
  ///
  /// A new entry only: the entry screen offers Repeat when recording, not
  /// when editing. Returns true when written. Then runs a catch-up, so a
  /// repeat started in the past posts its missed entries now, while the
  /// user is looking, rather than on the next launch.
  Future<bool> saveRepeating(RecurringRuleRequest request) async {
    state = const AsyncValue<void>.loading();

    final create = await ref.read(createRecurringRuleProvider.future);
    final result = await create(request);

    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        ref.read(recurringCatchUpProvider.notifier).run();
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

/// Records a transfer, exposing the attempt as an [AsyncValue].
///
/// Separate from [SaveTransactionController] because a transfer is not a
/// transaction with a different type on it: it writes three rows across two
/// tables in one database transaction (E-15), carries no category (E-17), and
/// has its own validation. One controller taking either would be a controller
/// with two unrelated halves.
class SaveTransferController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Validates and records [params].
  ///
  /// Returns true when it was written, so the caller can pop. The failure is
  /// left in [state] for the screen to show — including the validation ones,
  /// which are `MakeTransfer`'s own rather than restated here.
  Future<bool> save(TransferParams params) async {
    state = const AsyncValue<void>.loading();

    final makeTransfer = await ref.read(makeTransferProvider.future);
    final result = await makeTransfer(params);

    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        // No invalidation needed: entryAccountsProvider is a live stream over
        // the same DatabaseChangeBus the transfer's balance write publishes
        // to (see AccountRepositoryImpl.watch), so the two moved balances are
        // already on their way to the picker.
        return true;
      },
    );
  }
}

/// Controller for the transfer screen's save button. FR-TRF-002.
final saveTransferControllerProvider =
    AutoDisposeAsyncNotifierProvider<SaveTransferController, void>(
      SaveTransferController.new,
    );

/// The entry screen's inline `+`. E-13, FR-EXP-004.
///
/// Wraps [CategoryWriter] — the port in `core/ports/`, since this feature may
/// not import `features/categories/` (rule 4) — the same shape
/// [SaveTransferController] gives its own write.
class QuickAddCategoryController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates a category named [name], on the expense or income side per
  /// [isExpense], and returns its row id.
  ///
  /// Returns null on failure, with the reason left in [state] for the sheet
  /// to show — [CategoryWriter]'s own message, since it runs the same
  /// validation `AddCategory` does.
  Future<int?> call({required String name, required bool isExpense}) async {
    state = const AsyncValue<void>.loading();

    final writer = await ref.read(categoryWriterProvider.future);
    final result = await writer(name: name, isExpense: isExpense);

    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return null;
      },
      (id) {
        state = const AsyncValue<void>.data(null);
        // No invalidation needed (see SaveTransferController above):
        // entryCategoriesProvider is the same live stream CategoryListPage
        // reads, and the write already went through its repository. The
        // caller still has to wait for the new row's own arrival, though —
        // the stream update is asynchronous, not instantaneous.
        return id;
      },
    );
  }
}

/// Controller for the entry screen's inline category form.
final quickAddCategoryControllerProvider =
    AutoDisposeAsyncNotifierProvider<QuickAddCategoryController, void>(
      QuickAddCategoryController.new,
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

/// An expense's photo, decrypted, for the entry screen. FR-EXP-009.
///
/// A family on the path, disposed with its last watcher, as the scanner's
/// `receiptImageProvider` is: a photo leaves memory with the screen that
/// showed it. Null is a photo that is gone; a `Left` is the error.
final expensePhotoProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, path) async {
      final result = await ref.watch(loadExpensePhotoProvider)(path);
      return result.match(Future<Uint8List?>.error, Future<Uint8List?>.value);
    });

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
  /// The rows being deleted, for the photo each takes with it. FR-EXP-009.
  final Map<int, Transaction> _rows = {};
  AppLifecycleListener? _lifecycle;

  /// How long the user has to change their mind. Matches the snackbar.
  static const Duration window = Duration(seconds: 5);

  @override
  Set<int> build() {
    _lifecycle = AppLifecycleListener(onPause: _flush, onDetach: _flush);

    ref.onDispose(() {
      _lifecycle?.dispose();
      _lifecycle = null;
      _rows.clear();
    });
    return const {};
  }

  /// Hides [id] from the list. The caller drives when the write happens,
  /// either through [commit] (on snackbar close) or [_flush] (on background).
  ///
  /// Given the [row], a photo attached to it by hand is discarded once the
  /// delete is written — never before, so an undo brings the photo back.
  void schedule(int id, {Transaction? row}) {
    if (row != null) _rows[id] = row;
    state = {...state, id};
  }

  /// Puts [id] back, and never writes.
  void undo(int id) {
    _rows.remove(id);
    state = {...state}..remove(id);
  }

  /// Writes [id] now, if it is still pending. Idempotent: a second call
  /// after the row has been committed or undone is a no-op.
  void commit(int id) {
    if (!state.contains(id)) return;
    unawaited(_commit(id));
  }

  /// Writes every pending delete now, without waiting for its window.
  void _flush() {
    for (final id in state.toList()) {
      unawaited(_commit(id));
    }
  }

  Future<void> _commit(int id) async {
    final deleteTransaction = await ref.read(deleteTransactionProvider.future);
    final deleted = await deleteTransaction(id);
    final row = _rows.remove(id);
    if (deleted.isRight() && row != null) {
      await ref.read(discardUnusedPhotosProvider)(PhotoCleanup(before: row));
    }
    state = {...state}..remove(id);
  }
}

/// The rows hidden by an undo window that has not closed yet.
final pendingDeletionsProvider = NotifierProvider<PendingDeletions, Set<int>>(
  PendingDeletions.new,
);
