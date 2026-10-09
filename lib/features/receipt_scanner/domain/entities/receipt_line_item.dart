import 'package:equatable/equatable.dart';

/// One product line parsed off a receipt. FR-RCP-005, FR-RCP-006.
///
/// What `receipt_items` holds before a category is suggested: the name as
/// printed, the quantity, the unit price when the receipt printed one, and
/// the line total. The total is what becomes the expense (FR-RCP-009); the
/// quantity and unit price are context for the review screen and are never
/// summed.
///
/// [discountCents] and [chargesCents] say how the total was reached from
/// the figure printed against the line — `350.00 − 88.00 = 262.00` — so the
/// review screen can show the sum rather than ask to be trusted. They are
/// not stored: `receipt_items` keeps the total, which is what was spent.
class ReceiptLineItem extends Equatable {
  /// Creates a line item.
  const ReceiptLineItem({
    required this.name,
    required this.totalPriceCents,
    this.quantity = 1,
    this.unitPriceCents,
    this.discountCents = 0,
    this.chargesCents = 0,
  }) : assert(discountCents >= 0, 'a discount is never negative'),
       assert(chargesCents >= 0, 'a charge is never negative');

  /// The product description, as printed, with the figures stripped.
  final String name;

  /// How many. A `double` because receipts sell by weight (`1.5 KG`); this
  /// is a count, not money, so E-06 does not apply.
  final double quantity;

  /// The price of one, as printed or when it divides exactly. Before any
  /// discount: a discount is shown beside it, never folded into it.
  final int? unitPriceCents;

  /// What the line cost, minor units: the printed amount, less its
  /// discounts, plus its share of the bill's tax and charges. The expense.
  final int totalPriceCents;

  /// What came off the printed amount — the line's own discounts and its
  /// share of any discount on the whole bill. Zero when nothing did.
  final int discountCents;

  /// Its share of the tax and service charge the bill added on top of the
  /// prices. Zero when the prices included them.
  final int chargesCents;

  /// The amount printed against the line, before discounts and charges.
  int get printedCents => totalPriceCents + discountCents - chargesCents;

  /// True when [totalPriceCents] is not the printed amount.
  bool get isAdjusted => discountCents != 0 || chargesCents != 0;

  @override
  List<Object?> get props => [
    name,
    quantity,
    unitPriceCents,
    totalPriceCents,
    discountCents,
    chargesCents,
  ];
}
