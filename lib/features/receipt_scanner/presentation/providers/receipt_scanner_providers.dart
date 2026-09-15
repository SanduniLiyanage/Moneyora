/// Presentation state for the receipt scanner.
///
/// Talks to use cases and `core/ports` only — never a repository or
/// datasource — so a screen can be tested by overriding one provider in
/// `injection.dart`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/account_reader.dart';
import '../../../../core/ports/category_reader.dart';
import '../../../../injection.dart';
import '../../domain/entities/reviewed_receipt.dart';
import '../../domain/usecases/confirm_receipt.dart';

/// The expense categories the review screen offers per line, kept live.
/// FR-RCP-008.
///
/// Through [CategoryReader] because `features/receipt_scanner/` may not
/// import `features/categories/` (rule 4) — the same seam the entry screen
/// uses (E-27). Expense only: a receipt line filed under Salary is not a
/// mistake worth allowing, the rule the entry screen already applies.
final receiptCategoriesProvider = StreamProvider<List<CategoryOption>>((ref) {
  return Stream.fromFuture(ref.watch(categoryReaderProvider.future))
      .asyncExpand((reader) => reader.watchAll())
      .transform(
        StreamTransformer<
          Either<Failure, List<CategoryOption>>,
          List<CategoryOption>
        >.fromHandlers(
          handleData: (result, sink) => result.match(
            sink.addError,
            (all) => sink.add([
              for (final c in all)
                if (c.isExpense) c,
            ]),
          ),
        ),
      );
});

/// The non-archived accounts the review screen's picker offers, kept
/// live. FR-RCP-009 — every expense needs the account the money left.
final receiptAccountsProvider = StreamProvider<List<AccountOption>>((ref) {
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

/// Posts a reviewed receipt, exposing the attempt as an [AsyncValue].
/// FR-RCP-009 — `ConfirmReceipt`'s first caller from a screen.
///
/// The same shape as `SavePlanController`, for the same reason: a confirm
/// has three outcomes the screen must render, and `AsyncValue` has all
/// three. Returns what was written so the screen can say how many
/// expenses it made.
class ConfirmReceiptController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Writes the receipt; the failure — including `ConfirmReceipt`'s own
  /// refusals — is left in [state] for the screen to show.
  Future<ReceiptConfirmation?> confirm(ReviewedReceipt receipt) async {
    state = const AsyncValue<void>.loading();
    final confirmReceipt = await ref.read(confirmReceiptProvider.future);
    final result = await confirmReceipt(receipt);
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return null;
      },
      (confirmation) {
        state = const AsyncValue<void>.data(null);
        return confirmation;
      },
    );
  }
}

/// Controller for the review screen's Confirm button.
final confirmReceiptControllerProvider =
    AutoDisposeAsyncNotifierProvider<ConfirmReceiptController, void>(
      ConfirmReceiptController.new,
    );
