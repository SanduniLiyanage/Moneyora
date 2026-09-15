import 'package:equatable/equatable.dart';

import 'receipt_line_item.dart';

/// Where a scan is in its life. The `receipt_scans.status` check constraint.
enum ReceiptScanStatus {
  /// Captured, not yet reviewed.
  pending,

  /// Reviewed and posted to the ledger. FR-RCP-009.
  confirmed,

  /// Reviewed and thrown away.
  rejected,
}

/// One line of a stored scan: the item as parsed, what was suggested for
/// it, and what the user settled on. FR-RCP-009.
class ReceiptScanItem extends Equatable {
  /// Creates a stored item.
  const ReceiptScanItem({
    required this.item,
    required this.confidence,
    this.id,
    this.suggestedCategoryId,
    this.confirmedCategoryId,
  }) : assert(confidence >= 0 && confidence <= 100);

  /// Row id, null before it is saved.
  final int? id;

  /// The line as parsed, or as the user edited it on review.
  final ReceiptLineItem item;

  /// What the categoriser suggested (FR-RCP-007); null when nothing
  /// matched.
  final int? suggestedCategoryId;

  /// What the user kept or chose. Null until the scan is confirmed.
  final int? confirmedCategoryId;

  /// The suggestion's confidence, 0–100.
  final int confidence;

  @override
  List<Object?> get props => [
    id,
    item,
    suggestedCategoryId,
    confirmedCategoryId,
    confidence,
  ];
}

/// A receipt scan as the history keeps it. FR-RCP-009, FR-RCP-013, E-31.
///
/// The batch record FR-RCP-009 links every expense from one receipt under:
/// a transaction carries this row's id, so "which receipt was this from"
/// is one lookup and "what did this receipt buy" is one query. The header
/// fields mirror [ParsedReceipt]'s and are nullable for the same reason —
/// the review screen may leave what the parser could not read.
class ReceiptScan extends Equatable {
  /// Creates a scan record.
  const ReceiptScan({
    required this.imagePath,
    required this.status,
    this.id,
    this.merchantName,
    this.receiptDate,
    this.totalCents,
    this.taxCents,
    this.receiptNumber,
    this.confidence = 0,
    this.items = const [],
  }) : assert(confidence >= 0 && confidence <= 100);

  /// Row id, null before it is saved.
  final int? id;

  /// Where the photo lives on disk. FR-RCP-012's encryption at rest is a
  /// later slice; the path is what links the photo either way.
  final String imagePath;

  /// The store, as printed or as corrected.
  final String? merchantName;

  /// The date and time printed on the receipt, when read.
  final DateTime? receiptDate;

  /// The printed total, minor units.
  final int? totalCents;

  /// The printed tax or VAT figure, minor units.
  final int? taxCents;

  /// The receipt's own printed identifier (E-31).
  final String? receiptNumber;

  /// Overall confidence, 0–100.
  final int confidence;

  /// Pending, confirmed or rejected.
  final ReceiptScanStatus status;

  /// The lines kept, in printed order.
  final List<ReceiptScanItem> items;

  @override
  List<Object?> get props => [
    id,
    imagePath,
    merchantName,
    receiptDate,
    totalCents,
    taxCents,
    receiptNumber,
    confidence,
    status,
    items,
  ];
}
