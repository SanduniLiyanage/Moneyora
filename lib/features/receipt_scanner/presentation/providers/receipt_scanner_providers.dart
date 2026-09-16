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
import '../../domain/entities/receipt_image_source.dart';
import '../../domain/entities/receipt_scan.dart';
import '../../domain/entities/reviewed_receipt.dart';
import '../../domain/entities/scanned_receipt.dart';
import '../../domain/usecases/confirm_receipt.dart';
import '../../domain/usecases/get_scan_history.dart';

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

/// The read stage both scanning controllers end in: the path through
/// `ReadReceiptImage`, the failure left in [state] for the screen to
/// show, the result returned so the screen can open the review with it.
mixin _ReadsReceiptImage on AutoDisposeAsyncNotifier<void> {
  Future<ScannedReceipt?> readImage(String path) async {
    final read = await ref.read(readReceiptImageProvider.future);
    final result = await read(path);
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return null;
      },
      (scanned) {
        state = const AsyncValue<void>.data(null);
        return scanned;
      },
    );
  }
}

/// Gets a photo and reads it, exposing the attempt as an [AsyncValue].
/// FR-RCP-002, FR-RCP-004 — `PickReceiptImage` and `ReadReceiptImage`'s
/// first caller from a screen.
///
/// The same shape as [ConfirmReceiptController]: the screen renders the
/// wait, the failure and the result from one value. Returns what was
/// read so the screen can open the review with it, or null when the
/// user backed out of the picker — which is not a failure, and leaves
/// [state] as it was.
class ScanReceiptController extends AutoDisposeAsyncNotifier<void>
    with _ReadsReceiptImage {
  @override
  Future<void> build() async {}

  /// Picks from [source] and runs the pipeline; the failure — a refused
  /// permission, an unreadable photo — is left in [state] for the screen
  /// to show.
  Future<ScannedReceipt?> scan(ReceiptImageSource source) async {
    state = const AsyncValue<void>.loading();
    final pick = await ref.read(pickReceiptImageProvider.future);
    final picked = await pick(source);
    switch (picked) {
      case Left(value: final failure):
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return null;
      case Right(value: null):
        state = const AsyncValue<void>.data(null);
        return null;
      case Right(value: final chosen?):
        return readImage(chosen);
    }
  }
}

/// Controller for the capture screen's two buttons.
final scanReceiptControllerProvider =
    AutoDisposeAsyncNotifierProvider<ScanReceiptController, void>(
      ScanReceiptController.new,
    );

/// Reads a photo already on the phone again, exposing the attempt as an
/// [AsyncValue]. FR-RCP-014 — the history's Re-scan.
///
/// The same pipeline as [ScanReceiptController] from the picker onward,
/// and its own state on purpose: the capture screen sits under the
/// history in the stack watching [scanReceiptControllerProvider], and a
/// re-scan that failed there would print its message under the capture
/// screen's buttons when the user came back to them.
class RescanReceiptController extends AutoDisposeAsyncNotifier<void>
    with _ReadsReceiptImage {
  @override
  Future<void> build() async {}

  /// Runs the pipeline on [imagePath]; an unreadable photo is left in
  /// [state] for the screen to show.
  Future<ScannedReceipt?> rescan(String imagePath) {
    state = const AsyncValue<void>.loading();
    return readImage(imagePath);
  }
}

/// Controller for the history's Re-scan action.
final rescanReceiptControllerProvider =
    AutoDisposeAsyncNotifierProvider<RescanReceiptController, void>(
      RescanReceiptController.new,
    );

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

/// The receipts scanned so far, narrowed by what was typed into the
/// search field. FR-RCP-013 — `GetScanHistory`'s caller from a screen.
///
/// A family on the search text, the shape `planComparisonProvider` uses:
/// each distinct search is its own value, the previous one is kept while
/// the next loads, and leaving the screen drops them all. A `Left` is the
/// future's error so the screen shows the failure's own sentence.
final receiptHistoryProvider = FutureProvider.autoDispose
    .family<List<ReceiptScan>, String>((ref, search) async {
      final getHistory = await ref.watch(getScanHistoryProvider.future);
      final result = await getHistory(ReceiptHistoryQuery(search: search));
      return result.match(
        Future<List<ReceiptScan>>.error,
        Future<List<ReceiptScan>>.value,
      );
    });
