import 'package:equatable/equatable.dart';

import 'receipt_line_item.dart';

/// One line the user kept on the review screen, with the category they
/// settled on. FR-RCP-008, FR-RCP-009.
class ReviewedItem extends Equatable {
  /// Creates a reviewed line.
  const ReviewedItem({
    required this.item,
    required this.categoryId,
    this.suggestedCategoryId,
    this.confidence = 0,
  }) : assert(confidence >= 0 && confidence <= 100);

  /// The line, as parsed or as edited.
  final ReceiptLineItem item;

  /// The category the expense will carry — the suggestion kept, or the
  /// user's correction.
  final int categoryId;

  /// What the categoriser had suggested, kept so the record can say
  /// whether the user agreed (FR-RCP-015's learning reads this).
  final int? suggestedCategoryId;

  /// The suggestion's confidence, 0–100.
  final int confidence;

  /// True when the user chose something other than the suggestion.
  bool get wasCorrected =>
      suggestedCategoryId != null && suggestedCategoryId != categoryId;

  @override
  List<Object?> get props => [
    item,
    categoryId,
    suggestedCategoryId,
    confidence,
  ];
}

/// What the review screen hands over when the user taps Confirm.
/// FR-RCP-008, FR-RCP-009.
///
/// Not the [CategorisedReceipt] it opened with: by then items have been
/// edited, merged, split or discarded, and every kept line has a category
/// the user is answerable for. FR-RCP-010's single-category mode is one
/// [ReviewedItem] carrying the receipt total.
class ReviewedReceipt extends Equatable {
  /// Creates the reviewed receipt.
  const ReviewedReceipt({
    required this.imagePath,
    required this.accountId,
    required this.postedOn,
    required this.items,
    this.merchantName,
    this.receiptDate,
    this.totalCents,
    this.taxCents,
    this.receiptNumber,
  });

  /// The photo the scan was read from.
  final String imagePath;

  /// The account the money left.
  final int accountId;

  /// The day the expenses are recorded on. The screen defaults it to
  /// [receiptDate] when one was read, else today, and the user may change
  /// it — a receipt found in a coat pocket is dated when it was paid, not
  /// when it was scanned.
  final DateTime postedOn;

  /// The lines kept, in printed order.
  final List<ReviewedItem> items;

  /// The store, as printed or as corrected.
  final String? merchantName;

  /// The date and, when printed, the time on the receipt.
  final DateTime? receiptDate;

  /// The printed total, minor units.
  final int? totalCents;

  /// The printed tax or VAT figure, minor units.
  final int? taxCents;

  /// The receipt's own printed identifier (E-31).
  final String? receiptNumber;

  @override
  List<Object?> get props => [
    imagePath,
    accountId,
    postedOn,
    items,
    merchantName,
    receiptDate,
    totalCents,
    taxCents,
    receiptNumber,
  ];
}
