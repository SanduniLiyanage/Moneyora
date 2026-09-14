import 'package:equatable/equatable.dart';

import 'receipt_line_item.dart';

/// What the parser found on a receipt. FR-RCP-005, FR-RCP-006.
///
/// Every header field is nullable because every one can be missing or
/// illegible on a real receipt — FR-RCP-011 is built around that, and the
/// review screen (FR-RCP-008) lets the user fill in what the parser could
/// not. [items] is never null; a receipt with a total and no readable
/// lines is a valid parse that FR-RCP-010's single-category mode exists
/// for.
class ParsedReceipt extends Equatable {
  /// Creates a parse result.
  const ParsedReceipt({
    this.merchantName,
    this.receiptDate,
    this.items = const [],
    this.totalCents,
    this.taxCents,
    this.receiptNumber,
  });

  /// The store's name, as printed at the top.
  final String? merchantName;

  /// The date and, when printed, the time on the receipt. Time is midnight
  /// when only a date was read.
  final DateTime? receiptDate;

  /// The product lines, in printed order.
  final List<ReceiptLineItem> items;

  /// The printed total, minor units.
  final int? totalCents;

  /// The printed tax or VAT figure, minor units.
  final int? taxCents;

  /// The receipt's own printed identifier (E-31).
  final String? receiptNumber;

  /// What the item lines add up to.
  int get itemsSumCents =>
      items.fold(0, (sum, item) => sum + item.totalPriceCents);

  /// True when the parsed lines account for the printed total exactly —
  /// the cheapest evidence the parse is right. Null when there is no
  /// total to check against.
  bool? get itemsMatchTotal =>
      totalCents == null ? null : itemsSumCents == totalCents;

  @override
  List<Object?> get props => [
    merchantName,
    receiptDate,
    items,
    totalCents,
    taxCents,
    receiptNumber,
  ];
}
