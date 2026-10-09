import 'package:equatable/equatable.dart';

import '../../entities/payment_method.dart';
import '../../entities/receipt_line_item.dart';
import 'receipt_body.dart';
import 'receipt_vocabulary.dart';

/// The items as they were paid for, the total, and whether the two agree.
class ReceiptReconciliation extends Equatable {
  /// Creates the result.
  const ReceiptReconciliation({
    required this.items,
    this.totalCents,
    this.taxCents,
    this.totalGuessed = false,
  });

  /// The items, discounts off and charges on.
  final List<ReceiptLineItem> items;

  /// What was paid.
  final int? totalCents;

  /// The tax or VAT printed, when any was.
  final int? taxCents;

  /// True when [totalCents] was worked out, not read off a total line, and
  /// nothing else on the receipt bears it out — the items do not add up to
  /// it and no other figure gives it.
  final bool totalGuessed;

  @override
  List<Object?> get props => [items, totalCents, taxCents, totalGuessed];
}

/// Applies a receipt's discounts and charges to its items and checks the
/// result against its total. FR-RCP-005, FR-RCP-006, FR-RCP-011, E-45.
///
/// The last stage of `ParseReceiptText`, and the one that decides between
/// readings. The items have to add up to what was paid: that is the one
/// fact every receipt states twice, and the cheapest evidence a parse is
/// right. So a reading that does not add up is not the answer while
/// another one does.
///
/// Decisions the SRS does not make:
/// - **The total is the bill as paid**: the last line of the strongest
///   kind — `NET AMOUNT`, `GRAND TOTAL` before a plain `TOTAL` — never the
///   gross, the cash tendered or the change. With no total line, it is
///   the cash less the change, then the card payment, then the sub-total,
///   and marked as guessed unless the items or another figure bear it out.
/// - **A discount comes off the item it names.** By article code first
///   (`2 100334 25.20% Dis 92.00` is the toothpaste's), then by row number
///   when it is one of a block of discounts, then the item printed
///   directly above it. A discount that names no item, is printed after
///   the sub-total, says `BILL`, or is more than its item cost, is the
///   bill's, and is spread over every item in proportion to what each
///   still costs. A line taken to nothing is dropped — a cancelled item is
///   not an expense (FR-RCP-009 makes one of every item).
/// - **Proportional shares are whole cents and add up exactly.** Each item
///   takes its share rounded down, and the cents left over go to the
///   largest item, so the items still add up to what was paid.
/// - **Tax and charges on top of the prices are spread over the items** in
///   proportion, when the items alone fall short of the total by exactly
///   them — each expense is then what the item really cost. When the items
///   already add up, the prices included the tax and nothing is added.
///   The tax figure is the first tax line's either way: a receipt that
///   breaks VAT down by rate repeats the figure.
/// - **When the items do not add up, other readings are tried** before the
///   receipt is called unreadable, fewest departures first: a line that
///   repeats the items above it is a sub-total and dropped; a rate with no
///   amount (`DISCOUNT 10%`) is applied; a discount under an item is taken
///   as the bill's; the discount lines are taken as already in the prices.
///   The first reading that adds up is the answer. A printed rounding line
///   accounts for its own difference, put on the largest item.
/// - **No reading adds up: the receipt as printed** — discounts applied as
///   they name their items, nothing dropped — against its total. The
///   review screen then says the items fall short, which is the truth.
abstract final class ReceiptReconciler {
  /// Reconciles [body].
  static ReceiptReconciliation reconcile(ReceiptBody body) {
    final taxes = body.figures(LineRole.tax);
    final services = body.figures(LineRole.service);
    final tax = taxes.firstOrNull;
    final serviceSum = _sum(services);
    final charges = <int>{
      _sum(taxes) + serviceSum,
      (tax ?? 0) + serviceSum,
      tax ?? 0,
      serviceSum,
    }..remove(0);
    final rounding = body.figures(LineRole.rounding).firstOrNull?.abs();

    final totals = _totals(body);
    for (final total in totals) {
      for (final variant in _variants) {
        final read = _apply(body, variant);
        if (read == null) continue;
        final sum = _sum([for (final a in read) a.cost]);
        final found = switch (total.cents - sum) {
          0 => _priced(read),
          final short when charges.contains(short) => _priced(
            read,
            charge: short,
          ),
          final off when rounding != null && off.abs() == rounding => _priced(
            read,
            rounding: off,
          ),
          _ => null,
        };
        if (found != null) {
          return ReceiptReconciliation(
            items: found,
            totalCents: total.cents,
            taxCents: tax,
          );
        }
      }
    }

    final best =
        totals.where((t) => _confirmed(body, t.cents)).firstOrNull ??
        totals.firstOrNull;
    return ReceiptReconciliation(
      items: _priced(_apply(body, const _Variant())!),
      totalCents: best?.cents,
      taxCents: tax,
      totalGuessed: best != null && best.derived && best.sources < 2,
    );
  }

  /// [amount] shared over [weights] in proportion, in whole cents that add
  /// up to it exactly. Each takes its share rounded down; what is left goes
  /// to the largest weight — the first, on a tie — and, when [capped], no
  /// share is more than its weight, so a discount never takes an item
  /// below nothing.
  static List<int> allocate(
    int amount,
    List<int> weights, {
    bool capped = true,
  }) {
    final shares = List.filled(weights.length, 0);
    final whole = _sum(weights);
    if (amount <= 0 || whole <= 0) return shares;
    final spread = capped && amount > whole ? whole : amount;
    for (final (i, weight) in weights.indexed) {
      shares[i] = spread * weight ~/ whole;
    }
    var left = spread - _sum(shares);
    final largestFirst = [for (var i = 0; i < weights.length; i++) i]
      ..sort((a, b) {
        final byWeight = weights[b].compareTo(weights[a]);
        return byWeight != 0 ? byWeight : a.compareTo(b);
      });
    for (final i in largestFirst) {
      if (left == 0) break;
      final give = capped ? (weights[i] - shares[i]).clamp(0, left) : left;
      shares[i] += give;
      left -= give;
    }
    return shares;
  }

  /// The totals to try, best first: every total line, the strongest kind
  /// and the last printed first; failing any, the figures a total can be
  /// worked out from.
  static List<_Total> _totals(ReceiptBody body) {
    final net = body.figures(LineRole.net);
    final total = body.figures(LineRole.total);
    final labelled = [...net.reversed, ...total.reversed];
    if (labelled.isNotEmpty) {
      return [
        for (final cents in labelled.toSet()) _Total(cents, derived: false),
      ];
    }

    final tendered = _sum(body.figures(LineRole.tender));
    final change = body.figures(LineRole.change);
    final card = [
      for (final s in body.summaries)
        if (s.role == LineRole.tender && _isCard(s)) s.cents,
    ].firstOrNull;
    final gross = body.figures(LineRole.gross).lastOrNull;
    final worked = [
      if (change.isNotEmpty && tendered > _sum(change)) tendered - _sum(change),
      ?card,
      ?gross,
    ];
    return [
      for (final cents in worked.toSet())
        _Total(
          cents,
          derived: true,
          sources: worked.where((w) => w == cents).length,
        ),
    ];
  }

  static bool _isCard(SummaryLine line) => line.method == PaymentMethod.card;

  /// True when the receipt's own figures give [total] another way: the
  /// gross less the discounts printed, with or without the tax on top, or
  /// the money tendered less the change, with or without points spent.
  static bool _confirmed(ReceiptBody body, int total) {
    final discounts = _sum([for (final d in body.discounts) d.cents ?? 0]);
    final charges =
        _sum(body.figures(LineRole.tax)) + _sum(body.figures(LineRole.service));
    for (final gross in body.figures(LineRole.gross)) {
      if (gross - discounts == total) return true;
      if (gross - discounts + charges == total) return true;
    }
    final change = body.figures(LineRole.change);
    if (change.isEmpty) return false;
    final paid = _sum(body.figures(LineRole.tender)) - _sum(change);
    final points = _sum(body.figures(LineRole.points));
    return paid == total || paid + points == total;
  }

  /// The readings to try, fewest departures from the receipt as printed
  /// first.
  static const _variants = [
    _Variant(),
    _Variant(dropSubtotals: true),
    _Variant(applyRates: true),
    _Variant(belowOnBill: true),
    _Variant(ignoreDiscounts: true),
    _Variant(dropSubtotals: true, applyRates: true),
    _Variant(dropSubtotals: true, belowOnBill: true),
    _Variant(dropSubtotals: true, ignoreDiscounts: true),
    _Variant(applyRates: true, belowOnBill: true),
  ];

  /// The items under [variant], each with what came off it; null when the
  /// variant reads the receipt no differently from one already tried.
  static List<_Applied>? _apply(ReceiptBody body, _Variant variant) {
    final items = body.items;
    final printed = [for (final i in items) i.item.totalPriceCents];
    final keep = List.filled(items.length, true);
    if (variant.dropSubtotals) {
      var above = 0;
      for (var k = 0; k < items.length; k++) {
        if (_repeatsOthers(body, printed, k, above: above)) {
          keep[k] = false;
        } else {
          above += printed[k];
        }
      }
      if (keep.every((k) => k)) return null;
    }

    final off = List.filled(items.length, 0);
    final onBill = <int>[];
    if (variant.ignoreDiscounts) {
      if (body.discounts.every((d) => d.cents == null)) return null;
    } else {
      for (final discount in body.discounts) {
        final cents = discount.cents;
        if (cents == null || cents <= 0) continue;
        final target = _itemOf(discount, items, keep, variant);
        if (target != null && cents <= printed[target] - off[target]) {
          off[target] += cents;
        } else {
          onBill.add(cents);
        }
      }
    }
    if (variant.applyRates) {
      final rates = [
        for (final d in body.discounts)
          if (d.cents == null && d.percent != null) d.percent!,
      ];
      if (rates.isEmpty) return null;
      for (final rate in rates) {
        final base = _sum([
          for (var i = 0; i < items.length; i++)
            if (keep[i]) printed[i] - off[i],
        ]);
        // Basis points, so the rate is applied in integers.
        final basisPoints = (rate * 100).round();
        onBill.add((base * basisPoints + 5000) ~/ 10000);
      }
    }
    if (variant.belowOnBill &&
        !body.discounts.any((d) => d.belowItem != null && !d.onBill)) {
      return null;
    }

    for (final amount in onBill) {
      final remaining = [
        for (var i = 0; i < items.length; i++)
          keep[i] ? printed[i] - off[i] : 0,
      ];
      final shares = allocate(amount, remaining);
      for (var i = 0; i < items.length; i++) {
        off[i] += shares[i];
      }
    }

    return [
      for (var i = 0; i < items.length; i++)
        if (keep[i] && printed[i] - off[i] > 0)
          _Applied(items[i].item, printed: printed[i], off: off[i]),
    ];
  }

  /// The index of the item [discount] belongs to, or null when it is the
  /// bill's.
  static int? _itemOf(
    DiscountLine discount,
    List<ItemLine> items,
    List<bool> keep,
    _Variant variant,
  ) {
    int? where(bool Function(ItemLine) test) {
      for (var i = 0; i < items.length; i++) {
        if (keep[i] && test(items[i])) return i;
      }
      return null;
    }

    if (discount.code case final code?) {
      if (where((i) => i.code == code) case final i?) return i;
    }
    if (discount.rowNumber case final row?
        when discount.listed || discount.code != null) {
      if (where((i) => i.rowNumber == row) case final i?) return i;
    }
    final below = discount.belowItem;
    if (below != null &&
        !discount.onBill &&
        !variant.belowOnBill &&
        keep[below]) {
      return below;
    }
    return null;
  }

  /// True when item [k]'s amount is [above] — the sum of the items kept
  /// above it — or the sum of the items below it, or a total the receipt
  /// printed: a summary line OCR misread as an item.
  static bool _repeatsOthers(
    ReceiptBody body,
    List<int> printed,
    int k, {
    required int above,
  }) {
    if (printed.length < 2) return false;
    final belowIt = _sum(printed.sublist(k + 1));
    final amount = printed[k];
    if (above > 0 && amount == above) return true;
    if (k < printed.length - 1 && amount == belowIt) return true;
    return body.summaries.any(
      (s) =>
          (s.role == LineRole.net ||
              s.role == LineRole.total ||
              s.role == LineRole.gross) &&
          s.cents == amount,
    );
  }

  /// The items of [read] as paid: [charge] spread over them in proportion,
  /// and a [rounding] difference put on the largest.
  static List<ReceiptLineItem> _priced(
    List<_Applied> read, {
    int charge = 0,
    int rounding = 0,
  }) {
    final costs = [for (final a in read) a.cost];
    final charges = allocate(charge, costs, capped: false);
    final off = [for (final a in read) a.off];
    if (rounding != 0 && read.isNotEmpty) {
      final largest = allocate(1, costs, capped: false).indexOf(1);
      if (rounding > 0) {
        charges[largest] += rounding;
      } else {
        off[largest] -= rounding;
      }
    }
    return [
      for (final (i, a) in read.indexed)
        ReceiptLineItem(
          name: a.item.name,
          quantity: a.item.quantity,
          unitPriceCents: a.item.unitPriceCents,
          totalPriceCents: a.printed - off[i] + charges[i],
          discountCents: off[i],
          chargesCents: charges[i],
        ),
    ];
  }

  static int _sum(Iterable<int> values) => values.fold(0, (s, v) => s + v);
}

/// A total to try, and whether it was worked out rather than read.
class _Total {
  const _Total(this.cents, {required this.derived, this.sources = 1});

  final int cents;
  final bool derived;

  /// How many of the figures a total is worked out from give this one.
  final int sources;
}

/// One way of reading a receipt's discounts and lines.
class _Variant {
  const _Variant({
    this.dropSubtotals = false,
    this.applyRates = false,
    this.belowOnBill = false,
    this.ignoreDiscounts = false,
  });

  /// Drop items that repeat other items' sum or a printed total.
  final bool dropSubtotals;

  /// Apply rates printed with no amount.
  final bool applyRates;

  /// Take a discount under an item as the whole bill's.
  final bool belowOnBill;

  /// Take the discount lines as already in the prices.
  final bool ignoreDiscounts;
}

/// An item with what came off it.
class _Applied {
  const _Applied(this.item, {required this.printed, required this.off});

  final ReceiptLineItem item;
  final int printed;
  final int off;

  int get cost => printed - off;
}
