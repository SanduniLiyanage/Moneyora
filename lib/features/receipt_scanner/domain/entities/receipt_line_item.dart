import 'package:equatable/equatable.dart';

/// One product line parsed off a receipt. FR-RCP-005, FR-RCP-006.
///
/// What `receipt_items` holds before a category is suggested: the name as
/// printed, the quantity, the unit price when the receipt printed one, and
/// the line total. The total is what becomes the expense (FR-RCP-009); the
/// quantity and unit price are context for the review screen and are never
/// summed.
class ReceiptLineItem extends Equatable {
  /// Creates a line item.
  const ReceiptLineItem({
    required this.name,
    required this.totalPriceCents,
    this.quantity = 1,
    this.unitPriceCents,
  });

  /// The product description, as printed, with the figures stripped.
  final String name;

  /// How many. A `double` because receipts sell by weight (`1.5 KG`); this
  /// is a count, not money, so E-06 does not apply.
  final double quantity;

  /// The price of one, when the receipt printed it or it divides exactly.
  final int? unitPriceCents;

  /// The line total, minor units.
  final int totalPriceCents;

  @override
  List<Object?> get props => [name, quantity, unitPriceCents, totalPriceCents];
}
