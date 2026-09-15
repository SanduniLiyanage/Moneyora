import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// One expense as [ExpenseWriter] takes it. FR-RCP-009.
///
/// Primitives only, never the transactions feature's `Transaction` entity
/// — a consumer outside that feature must never need its domain types,
/// the rule [CategoryWriter] sets. What is missing is deliberate: no type
/// (always an expense), no transfer direction, no splits, no recurring
/// rule. A receipt line is the simplest expense there is.
class ExpenseToRecord extends Equatable {
  /// Creates the description of one expense.
  const ExpenseToRecord({
    required this.accountId,
    required this.categoryId,
    required this.amountCents,
    required this.date,
    this.time,
    this.note,
    this.receiptScanId,
    this.receiptImagePath,
  });

  /// The account the money left.
  final int accountId;

  /// The category the expense belongs to.
  final int categoryId;

  /// Minor units, positive.
  final int amountCents;

  /// The day it happened.
  final DateTime date;

  /// `HH:MM`, when known.
  final String? time;

  /// Free text for the transaction list.
  final String? note;

  /// The receipt scan that produced it — the batch FR-RCP-009 links every
  /// item under.
  final int? receiptScanId;

  /// The receipt photo, when there is one (FR-RCP-012).
  final String? receiptImagePath;

  @override
  List<Object?> get props => [
    accountId,
    categoryId,
    amountCents,
    date,
    time,
    note,
    receiptScanId,
    receiptImagePath,
  ];
}

/// Records expenses from outside `features/transactions/`. FR-RCP-009.
///
/// The receipt scanner turns every confirmed item into an expense, and
/// `features/receipt_scanner/` may not import `features/transactions/`
/// (`check_architecture.sh` rule 4) — so this is the seam between them,
/// the role [CategoryWriter] plays for the entry screen's inline `+`.
/// The transactions feature implements it, which is what keeps every
/// expense — typed, scanned or generated — under the one validation and
/// the one write path that moves `accounts.current_balance_cents` (E-18).
abstract class ExpenseWriter {
  /// Records [expenses] as one unit — every row or none — returning their
  /// ids in the same order.
  ///
  /// A receipt is one purchase however many lines it has, and a user who
  /// sees "could not save" must be able to tap again without finding half
  /// the items already in the ledger. Every expense is validated before
  /// any is written, so a bad line fails the whole batch up front.
  Future<Either<Failure, List<int>>> call(List<ExpenseToRecord> expenses);
}
