/// Presentation state for the accounts feature.
///
/// These talk to **use cases**, never to a repository or a datasource, which
/// is the rule `scripts/check_architecture.sh` enforces and the reason a
/// screen can be tested by overriding one provider.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../injection.dart';
import '../../domain/entities/account.dart';

/// The accounts, kept live, archived ones included only when asked.
///
/// A `StreamProvider` rather than a future because a balance is the most
/// derived thing on any screen: it moves whenever a transaction is written
/// anywhere, and a screen that read it once would be wrong by the time the
/// user looked back at it.
///
/// That only works because `injection.dart` hands both datasources one
/// `DatabaseChangeBus` — the balance is moved by the *transactions*
/// datasource, so without the shared signal this stream would never re-read
/// after an expense. See `core/database/database_change_bus.dart`.
final accountsProvider = StreamProvider.family<List<Account>, bool>((
  ref,
  includeArchived,
) {
  return Stream.fromFuture(ref.watch(watchAccountsProvider.future))
      .asyncExpand((watchAccounts) => watchAccounts(includeArchived))
      // A `Left` goes down the error channel so it arrives as
      // `AsyncValue.error` and each screen handles it in the branch its
      // `switch` already has. `sink.addError` rather than `throw`: a `Failure`
      // is a value, not an exception, and ARCHITECTURE.md §3 keeps those two
      // vocabularies apart deliberately.
      .transform(
        StreamTransformer<
          Either<Failure, List<Account>>,
          List<Account>
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

/// Saves an account, exposing the attempt as an [AsyncValue].
///
/// An `AsyncNotifier` rather than local widget state because a save has three
/// outcomes the form must render — in flight, failed, done — and `AsyncValue`
/// has no "success only" shape to forget about. The same shape as
/// `SaveTransactionController`, for the same reason.
class SaveAccountController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates [account], or updates it when it already has an id.
  ///
  /// One method rather than two because the form is one form, and a caller
  /// that has to know which to call is a caller that can pick wrong.
  ///
  /// Returns true when it was written, so the caller can pop. The failure is
  /// left in [state] for the form to show — including the validation ones,
  /// which come from `AddAccount.validate` rather than being restated here.
  Future<bool> save(Account account) async {
    state = const AsyncValue<void>.loading();

    // The two use cases return different Right types — a new id, or unit —
    // and this cares about neither, only whether it worked.
    final Either<Failure, void> result;
    if (account.id == null) {
      final addAccount = await ref.read(addAccountProvider.future);
      result = await addAccount(account);
    } else {
      final updateAccount = await ref.read(updateAccountProvider.future);
      result = await updateAccount(account);
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

/// Controller for the account form's save button.
final saveAccountControllerProvider =
    AutoDisposeAsyncNotifierProvider<SaveAccountController, void>(
      SaveAccountController.new,
    );
