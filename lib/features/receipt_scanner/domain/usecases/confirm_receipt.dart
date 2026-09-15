import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/expense_writer.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/receipt_scan.dart';
import '../entities/reviewed_receipt.dart';
import '../repositories/keyword_dictionary_repository.dart';
import '../repositories/receipt_repository.dart';

/// What confirming produced: the batch record and the expenses under it.
class ReceiptConfirmation extends Equatable {
  /// Creates the result.
  const ReceiptConfirmation({
    required this.scanId,
    required this.transactionIds,
  });

  /// The `receipt_scans` row.
  final int scanId;

  /// One transaction per kept item, in the receipt's order.
  final List<int> transactionIds;

  @override
  List<Object?> get props => [scanId, transactionIds];
}

/// Posts a reviewed receipt to the ledger. FR-RCP-009, FR-RCP-015.
///
/// The seventh stage of the pipeline (SDD §7.2), after the review screen:
/// one expense per kept item, every one linked to a single scan record —
/// the "Receipt Batch" the SRS asks for — the dictionary taught every
/// line the user categorised differently from the suggestion, and one
/// more use counted on every mapping the user ended up agreeing with.
///
/// ## Three writes, in an order chosen for what a retry does
///
/// The scan record, the usage counts and the expenses live in two
/// features, and `features/receipt_scanner/` reaches the ledger only
/// through the [ExpenseWriter] port — so they cannot share one database
/// transaction. What can be chosen is the order, and it is chosen so that
/// **money is never recorded twice**:
///
/// 1. the scan and its items, as `confirmed` — a `transactions` row
///    needs the scan's id for its foreign key, so this goes first;
/// 2. per line, the lesson when there is one (FR-RCP-015), then the
///    usage count — in that order, so a correction is counted as applied
///    on the very line that taught it;
/// 3. the expenses, as one batch — all rows or none.
///
/// A failure at any step returns its failure and the user confirms again.
/// Before step 3 nothing has reached the ledger, so a retry costs a stray
/// scan record at most. A failure *in* step 3 leaves a confirmed scan with
/// no expenses under it: visible in FR-RCP-013's history, re-processed by
/// FR-RCP-014, and still nothing in the ledger. The reverse order would
/// leave expenses with no record, and a retry would post them again.
///
/// Every line is checked before step 1 — a blank name, a zero amount, a
/// date in the future — because the expense writer runs the same checks
/// and a refusal there would strand the scan record written in step 1.
///
/// The scan's confidence is the mean of its items', the figure FR-RCP-011
/// badges; an overall OCR score does not exist yet and this is the
/// cheapest honest stand-in.
class ConfirmReceipt implements UseCase<ReceiptConfirmation, ReviewedReceipt> {
  /// Creates the use case over the scan records, the dictionary and the
  /// ledger's write port.
  const ConfirmReceipt(this._receipts, this._dictionary, this._expenses);

  final ReceiptRepository _receipts;
  final KeywordDictionaryRepository _dictionary;
  final ExpenseWriter _expenses;

  @override
  Future<Either<Failure, ReceiptConfirmation>> call(
    ReviewedReceipt params,
  ) async {
    if (validate(params) case final failure?) return Left(failure);

    final saved = await _receipts.confirmScan(toScan(params));
    final int scanId;
    switch (saved) {
      case Left(value: final failure):
        return Left(failure);
      case Right(value: final id):
        scanId = id;
    }

    for (final item in params.items) {
      if (item.needsLearning) {
        final learnt = await _dictionary.learn(
          text: item.item.name,
          categoryId: item.categoryId,
        );
        if (learnt case Left(value: final failure)) return Left(failure);
      }
      final counted = await _dictionary.recordApplied(
        text: item.item.name,
        categoryId: item.categoryId,
      );
      if (counted case Left(value: final failure)) return Left(failure);
    }

    final posted = await _expenses(toExpenses(params, scanId: scanId));
    return posted.map(
      (ids) => ReceiptConfirmation(scanId: scanId, transactionIds: ids),
    );
  }

  /// Returns the reason [receipt] cannot be posted, or null if it can.
  ///
  /// Public and static so the review screen can disable Confirm with the
  /// same rules rather than a copy of them.
  static ValidationFailure? validate(ReviewedReceipt receipt) {
    if (receipt.imagePath.trim().isEmpty) {
      return const ValidationFailure('The receipt has no photo.');
    }
    if (receipt.items.isEmpty) {
      return const ValidationFailure('Keep at least one item.');
    }
    for (final (index, reviewed) in receipt.items.indexed) {
      if (reviewed.item.name.trim().isEmpty) {
        return ValidationFailure(
          'Item ${index + 1} needs a name.',
          field: 'items[$index].name',
        );
      }
      if (reviewed.item.totalPriceCents <= 0) {
        return ValidationFailure(
          'Item ${index + 1} needs an amount greater than zero.',
          field: 'items[$index].amount',
        );
      }
    }
    if (receipt.postedOn.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      // The same day of slack AddTransaction allows, for the same reason.
      return const ValidationFailure(
        'That date is in the future.',
        field: 'postedOn',
      );
    }
    return null;
  }

  /// The record to store for [receipt], status `confirmed`.
  static ReceiptScan toScan(ReviewedReceipt receipt) => ReceiptScan(
    imagePath: receipt.imagePath,
    status: ReceiptScanStatus.confirmed,
    merchantName: receipt.merchantName,
    receiptDate: receipt.receiptDate,
    totalCents: receipt.totalCents,
    taxCents: receipt.taxCents,
    receiptNumber: receipt.receiptNumber,
    confidence: meanConfidence(receipt.items),
    items: [
      for (final reviewed in receipt.items)
        ReceiptScanItem(
          item: reviewed.item,
          suggestedCategoryId: reviewed.suggestedCategoryId,
          confirmedCategoryId: reviewed.categoryId,
          confidence: reviewed.confidence,
        ),
    ],
  );

  /// One expense per kept item, linked to [scanId].
  ///
  /// The note is the item's name, with the merchant in brackets when one
  /// is known: the transaction list shows the note and nothing else from
  /// the receipt, and "BREAD" alone does not say where.
  static List<ExpenseToRecord> toExpenses(
    ReviewedReceipt receipt, {
    required int scanId,
  }) {
    final merchant = receipt.merchantName?.trim();
    final time = timeOf(receipt.receiptDate);
    return [
      for (final reviewed in receipt.items)
        ExpenseToRecord(
          accountId: receipt.accountId,
          categoryId: reviewed.categoryId,
          amountCents: reviewed.item.totalPriceCents,
          date: receipt.postedOn,
          time: time,
          note: merchant == null || merchant.isEmpty
              ? reviewed.item.name
              : '${reviewed.item.name} ($merchant)',
          receiptScanId: scanId,
          receiptImagePath: receipt.imagePath,
        ),
    ];
  }

  /// The mean of the items' confidences, rounded; 0 for none.
  static int meanConfidence(List<ReviewedItem> items) {
    if (items.isEmpty) return 0;
    final sum = items.fold(0, (s, i) => s + i.confidence);
    return (sum / items.length).round();
  }

  /// `HH:MM` when [receiptDate] carries a time, null when it is midnight
  /// — the parser's "only a date was read" (see [ParsedReceipt]).
  static String? timeOf(DateTime? receiptDate) {
    if (receiptDate == null) return null;
    if (receiptDate.hour == 0 && receiptDate.minute == 0) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(receiptDate.hour)}:${two(receiptDate.minute)}';
  }
}
