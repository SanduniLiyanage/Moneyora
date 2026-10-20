/// Presentation state for the debts feature.
///
/// These talk to **use cases**, never to a repository or a datasource, which
/// is the rule `scripts/check_architecture.sh` enforces and the reason a
/// screen can be tested by overriding one provider.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/account_reader.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../injection.dart';
import '../../domain/entities/debt.dart';
import '../../domain/entities/debt_person.dart';
import '../../domain/usecases/rename_person.dart';
import '../../domain/usecases/set_debt_paid.dart';
import '../../domain/usecases/settle_up.dart';
import '../../domain/usecases/split_bill.dart';

/// Every debt, open ones first, kept live. FR-DBT-002.
///
/// A `Left` goes down the stream's error channel, as `accountsProvider`
/// sends it, so the screen handles it in the branch its `.when` already
/// has.
final debtsProvider = StreamProvider<List<Debt>>((ref) {
  return Stream.fromFuture(ref.watch(watchDebtsProvider.future))
      .asyncExpand((watchDebts) => watchDebts(const NoParams()))
      .transform(
        StreamTransformer<Either<Failure, List<Debt>>, List<Debt>>.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

/// Every account that is not archived, kept live, for a debt to name the
/// one its money moved through. FR-DBT-009, E-47.
///
/// Read through [AccountReader], the port, as the entry screen reads them:
/// the accounts are another feature's.
final debtAccountsProvider = StreamProvider<List<AccountOption>>((ref) {
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

/// Saves a debt from the form, exposing the attempt as an [AsyncValue].
/// FR-DBT-001.
class SaveDebtController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Validates and saves [debt]; true when it was written. The failure is
  /// left in [state] for the form to show.
  Future<bool> save(Debt debt) async {
    state = const AsyncValue<void>.loading();
    final saveDebt = await ref.read(saveDebtProvider.future);
    final result = await saveDebt(debt);
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

/// Controller for the debt form's Save.
final saveDebtControllerProvider =
    AutoDisposeAsyncNotifierProvider<SaveDebtController, void>(
      SaveDebtController.new,
    );

/// Splits a bill and saves the debts it leaves. FR-DBT-004.
class SplitBillController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Splits and saves [request]; true when the debts were written. The
  /// failure is left in [state] for the screen to show.
  Future<bool> split(SplitRequest request) async {
    state = const AsyncValue<void>.loading();
    final splitBill = await ref.read(splitBillProvider.future);
    final result = await splitBill(request);
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

/// Controller for the split screen's Save.
final splitBillControllerProvider =
    AutoDisposeAsyncNotifierProvider<SplitBillController, void>(
      SplitBillController.new,
    );

/// Marking paid, opening again, and deleting. FR-DBT-003.
///
/// Each returns the failure, or null when it worked, for the caller to
/// say in a snackbar: these are taps on a row, with no field to show an
/// error beside.
class DebtActionsController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// [debt] paid on [paidOn] back through the account [through], or open
  /// again when [paidOn] is null.
  Future<Failure?> setPaid(
    Debt debt, {
    required DateTime? paidOn,
    int? through,
  }) async {
    final setDebtPaid = await ref.read(setDebtPaidProvider.future);
    return _settle(
      await setDebtPaid(DebtPayment(debt, paidOn: paidOn, through: through)),
    );
  }

  /// Removes the debt with [id].
  Future<Failure?> delete(int id) async {
    final deleteDebt = await ref.read(deleteDebtProvider.future);
    return _settle(await deleteDebt(id));
  }

  /// [person] called [to] on every record. FR-DBT-006.
  Future<Failure?> rename(DebtPerson person, {required String to}) async {
    final renamePerson = await ref.read(renamePersonProvider.future);
    return _settle(await renamePerson(PersonRename(person, to: to)));
  }

  /// Settles up with [person] [on] a day: what was written, for Undo, or
  /// the failure. FR-DBT-007.
  Future<Either<Failure, Settled>> settleUp(
    DebtPerson person, {
    required DateTime on,
    int? through,
  }) async {
    final settleUp = await ref.read(settleUpProvider.future);
    final result = await settleUp(Settlement(person, on: on, through: through));
    _settle(result.map((_) => unit));
    return result;
  }

  /// Takes [settled] back. FR-DBT-007.
  Future<Failure?> undoSettleUp(Settled settled) async {
    final undo = await ref.read(undoSettleUpProvider.future);
    return _settle(await undo(settled));
  }

  Failure? _settle(Either<Failure, Unit> result) => result.match(
    (failure) {
      state = AsyncValue<void>.error(failure, StackTrace.current);
      return failure;
    },
    (_) {
      state = const AsyncValue<void>.data(null);
      return null;
    },
  );
}

/// Controller for the list's and the form's paid and delete actions.
final debtActionsControllerProvider =
    AutoDisposeAsyncNotifierProvider<DebtActionsController, void>(
      DebtActionsController.new,
    );
