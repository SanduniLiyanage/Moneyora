import 'package:equatable/equatable.dart';

import '../../entities/payment_method.dart';
import '../../entities/receipt_line_item.dart';
import 'receipt_vocabulary.dart';

/// An item as printed, before any discount or charge is applied to it.
class ItemLine extends Equatable {
  /// Creates the line.
  const ItemLine(this.item, {this.rowNumber, this.code});

  /// The item at its printed amount.
  final ReceiptLineItem item;

  /// The row number printed before it — `1` in `1 126285 SAFEGUARD …`.
  final int? rowNumber;

  /// Its article code — `126285` — which a discount line may name it by.
  final String? code;

  /// This line with [more] added to its name: a name the receipt wrapped.
  ItemLine withMoreName(String more) => ItemLine(
    ReceiptLineItem(
      name: '${item.name} $more',
      quantity: item.quantity,
      unitPriceCents: item.unitPriceCents,
      totalPriceCents: item.totalPriceCents,
    ),
    rowNumber: rowNumber,
    code: code,
  );

  @override
  List<Object?> get props => [item, rowNumber, code];
}

/// A discount as printed, before it is matched to an item.
class DiscountLine extends Equatable {
  /// Creates the line.
  const DiscountLine({
    this.cents,
    this.percent,
    this.code,
    this.rowNumber,
    this.belowItem,
    this.listed = false,
    this.onBill = false,
  });

  /// What comes off, minor units, positive; null for a rate with no amount
  /// (`DISCOUNT 10%`).
  final int? cents;

  /// The rate printed on the line, when one is.
  final double? percent;

  /// The article code it names — the item it belongs to.
  final String? code;

  /// The row number printed before it.
  final int? rowNumber;

  /// The index of the item printed directly above it, when nothing but
  /// other discounts came between.
  final int? belowItem;

  /// True when it is one of a block of discounts under a heading, apart
  /// from the items — its row number is then an item's, not its own.
  final bool listed;

  /// True when it is the whole bill's: printed after the sub-total, or
  /// saying `BILL`.
  final bool onBill;

  @override
  List<Object?> get props => [
    cents,
    percent,
    code,
    rowNumber,
    belowItem,
    listed,
    onBill,
  ];
}

/// A priced line that is not an item or a discount: what it says, and its
/// figure.
class SummaryLine extends Equatable {
  /// Creates the line.
  const SummaryLine(this.role, this.cents, {this.method});

  /// What the line says about the bill.
  final LineRole role;

  /// Its figure, minor units.
  final int cents;

  /// Cash or card, for a tender line that says which.
  final PaymentMethod? method;

  @override
  List<Object?> get props => [role, cents, method];
}

/// Everything priced on a receipt, sorted by what it is but not yet
/// reconciled. What `ReceiptBodyReader` reads and `ReceiptReconciler`
/// checks.
class ReceiptBody extends Equatable {
  /// Creates the body.
  const ReceiptBody({
    this.items = const [],
    this.discounts = const [],
    this.summaries = const [],
    this.paymentMethod,
  });

  /// The items, in printed order, at their printed amounts.
  final List<ItemLine> items;

  /// The discounts, in printed order.
  final List<DiscountLine> discounts;

  /// The totals, taxes, payments, change and the rest, in printed order.
  final List<SummaryLine> summaries;

  /// How the receipt says it was paid, or null when no line said.
  final PaymentMethod? paymentMethod;

  /// The figures of the lines with [role], in printed order.
  List<int> figures(LineRole role) => [
    for (final s in summaries)
      if (s.role == role) s.cents,
  ];

  @override
  List<Object?> get props => [items, discounts, summaries, paymentMethod];
}
