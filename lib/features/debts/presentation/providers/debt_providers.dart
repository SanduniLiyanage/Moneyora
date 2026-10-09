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
import '../../../../core/usecases/usecase.dart';
import '../../../../injection.dart';
import '../../domain/entities/debt.dart';
import '../../domain/usecases/set_debt_paid.dart';

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

/// Marking paid, opening again, and deleting. FR-DBT-003.
///
/// Each returns the failure, or null when it worked, for the caller to
/// say in a snackbar: these are taps on a row, with no field to show an
/// error beside.
class DebtActionsController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// [debt] paid on [paidOn], or open again when null.
  Future<Failure?> setPaid(Debt debt, {required DateTime? paidOn}) async {
    final setDebtPaid = await ref.read(setDebtPaidProvider.future);
    return _settle(await setDebtPaid(DebtPayment(debt, paidOn: paidOn)));
  }

  /// Removes the debt with [id].
  Future<Failure?> delete(int id) async {
    final deleteDebt = await ref.read(deleteDebtProvider.future);
    return _settle(await deleteDebt(id));
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
