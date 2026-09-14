import 'package:equatable/equatable.dart';

import 'category_suggestion.dart';
import 'parsed_receipt.dart';
import 'receipt_line_item.dart';

/// One parsed item with the category suggested for it. FR-RCP-007.
class CategorisedItem extends Equatable {
  /// Creates the pair.
  const CategorisedItem({required this.item, required this.suggestion});

  /// The line as parsed.
  final ReceiptLineItem item;

  /// What the categoriser suggests for it.
  final CategorySuggestion suggestion;

  @override
  List<Object?> get props => [item, suggestion];
}

/// A parsed receipt with a category suggested for every item, and the
/// merchant's own category when the dictionary knows one. FR-RCP-007.
///
/// What the review screen (FR-RCP-008) opens with.
class CategorisedReceipt extends Equatable {
  /// Creates the result.
  const CategorisedReceipt({
    required this.receipt,
    required this.items,
    this.merchantCategoryId,
    this.merchantCategoryName,
  });

  /// The parse the suggestions were made for.
  final ParsedReceipt receipt;

  /// One entry per item of [receipt], in the same order.
  final List<CategorisedItem> items;

  /// The category the dictionary gives the merchant — a pharmacy's Health —
  /// or null when its name matched nothing. Layer 3's context, kept so the
  /// screen can say why an item was biased.
  final int? merchantCategoryId;

  /// Its display name.
  final String? merchantCategoryName;

  @override
  List<Object?> get props => [
    receipt,
    items,
    merchantCategoryId,
    merchantCategoryName,
  ];
}
