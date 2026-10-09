import '../../entities/payment_method.dart';
import 'priced_line.dart';
import 'receipt_body.dart';
import 'receipt_vocabulary.dart';

/// The items, the discounts and the totals, from a receipt's lines, each
/// sorted by what it says and nothing yet added up. FR-RCP-005,
/// FR-RCP-006.
///
/// The second stage of `ParseReceiptText`, after `ReceiptHeaderReader` has
/// taken the lines it used. A receipt is read as three bands. The
/// **header** runs to the first item. The **body** runs from there to the
/// total or the payment: every priced line in it is an item unless its
/// label makes it something else. The **footer** is everything after: the
/// cash, the change, the points, "thank you" — priced, and never items.
///
/// Decisions the SRS does not make:
/// - **A priced line's label decides what it is**, in the order
///   [ReceiptVocabulary.roleOf] asks: points, change, rounding, a summary
///   of discounts, a count, the gross, the tax, a service charge, the
///   total, a payment. What is none of those is a discount when it says so
///   (with or without its minus — OCR loses one as often as it keeps it),
///   is negative, or sits in a block under `Discounts`; otherwise an item.
/// - **A total above the first item ends nothing.** An e-bill prints `Your
///   bill for this transaction: 535.00` before its table; it is the total,
///   and the items below it are still items.
/// - **The first item is a price with cents, or a quantity multiplied
///   out.** A header line that merely ends in digits (`COLOMBO 03`) is not
///   a price. Inside the body, whole-rupee figures are prices.
/// - **Lines of words with no price join the priced line beneath them**
///   when that line has no words of its own: ML Kit reads a two-line item
///   — the name, then `2 x 240.00  480.00` — as two lines. A boutique
///   prints three, so every unpriced line since the last priced one joins.
/// - **A short fragment under a numbered row ends that row's name.** An
///   e-bill wraps `SAFEGUARD SOAP MULTIPACK 280G` onto `4S`; when the next
///   row is the next number, or the table ends, the fragment is the soap's.
///   On a receipt without row numbers a line of words above a priced line
///   with its own words is a heading, and dropped.
/// - **The merchant line never joins** — the header reader has it.
/// - **A line priced at nothing is not an item.** A free bag at 0.00 is not
///   an expense.
class ReceiptBodyReader {
  /// Creates a reader over [vocabulary].
  const ReceiptBodyReader(this._vocabulary);

  final ReceiptVocabulary _vocabulary;

  /// `BILL DISCOUNT`, `DISCOUNT ON TOTAL`: a discount on the whole bill.
  static final _onBill = RegExp(
    r'\b(?:bill|total|invoice|basket|cart)\b',
    caseSensitive: false,
  );

  static final _percent = RegExp(r'(\d{1,3}(?:\.\d{1,2})?)\s*%');

  /// Reads [lines], passing over the indexes in [skip].
  ReceiptBody read(List<String> lines, {Set<int> skip = const {}}) {
    final items = <ItemLine>[];
    final discounts = <DiscountLine>[];
    final summaries = <SummaryLine>[];
    PaymentMethod? paidBy;

    var band = _Band.header;
    // The lines of words since the last priced line: the name of a
    // multi-line item, a wrapped name, a heading, or a rate.
    final pending = <String>[];
    var inDiscounts = false;
    var afterGross = false;
    // The item printed directly above, while only discounts came between.
    int? below;

    // Settles the words since the last priced line when the next line will
    // not take them: the end of a numbered row's wrapped name when [wraps]
    // and they look like one; a rate the bill takes off (`DISCOUNT 10%`);
    // otherwise a heading, dropped.
    void settle({required bool wraps}) {
      if (pending.isEmpty) return;
      final fragment = pending.join(' ');
      if (wraps &&
          band == _Band.body &&
          !inDiscounts &&
          items.isNotEmpty &&
          items.last.rowNumber != null &&
          _isWrap(fragment)) {
        items[items.length - 1] = items.last.withMoreName(fragment);
      } else if (band == _Band.body) {
        for (final line in pending) {
          final rate = _percent.firstMatch(line)?[1];
          if (rate != null && _vocabulary.discountWord.hasMatch(line)) {
            discounts.add(
              DiscountLine(percent: double.parse(rate), onBill: true),
            );
          }
        }
      }
      pending.clear();
    }

    for (final (i, raw) in lines.indexed) {
      if (skip.contains(i)) {
        settle(wraps: false);
        continue;
      }
      final line = PricedLine.collapse(raw);
      if (line.isEmpty) continue;
      final isColumnTitles = ReceiptVocabulary.columnTitles.hasMatch(line);
      if (isColumnTitles ||
          ReceiptVocabulary.noise.hasMatch(line) ||
          (band == _Band.header &&
              ReceiptVocabulary.headerNoise.hasMatch(line))) {
        if (isColumnTitles) inDiscounts = false;
        settle(wraps: false);
        continue;
      }

      final priced = PricedLine.of(line);
      if (priced == null) {
        if (band != _Band.header &&
            _vocabulary.discountHeading.hasMatch(line)) {
          settle(wraps: true);
          // `DISCOUNT 10%` heads the lines that apply it, or is the bill's
          // rate with no amount printed; the reconciler applies the rate
          // only when that is what adds up.
          if (_percent.firstMatch(line)?[1] case final rate?) {
            discounts.add(
              DiscountLine(percent: double.parse(rate), onBill: true),
            );
          }
          inDiscounts = true;
          below = null;
          continue;
        }
        if (band != _Band.header &&
            ReceiptVocabulary.paymentPrefix.hasMatch(line)) {
          paidBy ??= _vocabulary.methodOf(line);
          settle(wraps: false);
          continue;
        }
        pending.add(line);
        continue;
      }

      // A wordless priced line completes the words above it.
      final joins = priced.isWordless && pending.isNotEmpty;
      final effective = joins
          ? PricedLine.of('${pending.join(' ')} ${priced.line}')!
          : priced;
      final role = _vocabulary.roleOf(effective.rest);
      if (joins) {
        pending.clear();
      } else {
        final last = items.lastOrNull?.rowNumber;
        final nextRow = effective.rowNumber;
        settle(
          wraps:
              role != null ||
              (last != null && nextRow != null && nextRow == last + 1),
        );
      }

      if (role != null) {
        if (band == _Band.header && !_headerRoles.contains(role)) continue;
        summaries.add(
          SummaryLine(
            role,
            effective.cents,
            method: role == LineRole.tender
                ? _vocabulary.methodOf(effective.rest)
                : null,
          ),
        );
        switch (role) {
          case LineRole.gross:
            afterGross = true;
          case LineRole.net || LineRole.total || LineRole.change:
            if (band == _Band.body) band = _Band.footer;
          case LineRole.tender:
            paidBy ??= _vocabulary.methodOf(effective.rest);
            if (band == _Band.body) band = _Band.footer;
          default:
        }
        inDiscounts = false;
        below = null;
        continue;
      }
      if (band == _Band.footer) continue;

      if (band == _Band.body &&
          (effective.cents < 0 ||
              inDiscounts ||
              _vocabulary.discountWord.hasMatch(effective.rest))) {
        discounts.add(
          DiscountLine(
            cents: effective.cents.abs(),
            percent: effective.percent,
            code: effective.code,
            rowNumber: effective.rowNumber,
            belowItem: inDiscounts ? null : below,
            listed: inDiscounts,
            onBill: afterGross || _onBill.hasMatch(effective.rest),
          ),
        );
        continue;
      }
      if (effective.cents <= 0) continue;
      if (band == _Band.header && !effective.startsBody) continue;
      // A discount before any item has nothing to come off.
      if (_vocabulary.discountWord.hasMatch(effective.rest)) continue;

      band = _Band.body;
      if (effective.toItem() case final item?) {
        items.add(
          ItemLine(item, rowNumber: effective.rowNumber, code: effective.code),
        );
        below = items.length - 1;
      }
    }
    settle(wraps: true);

    return ReceiptBody(
      items: items,
      discounts: discounts,
      summaries: summaries,
      paymentMethod: paidBy,
    );
  }

  /// The roles a line above the first item can have: a total printed over
  /// the table, and the tax beside it. A payment or change up there is a
  /// heading's word, not a figure.
  static const _headerRoles = {
    LineRole.net,
    LineRole.total,
    LineRole.gross,
    LineRole.tax,
    LineRole.service,
  };

  /// Up to three words with no discount, rate or role in them: `4S`,
  /// `200G PKT`.
  bool _isWrap(String fragment) =>
      fragment.split(' ').length <= 3 &&
      !fragment.contains('%') &&
      !_vocabulary.discountWord.hasMatch(fragment) &&
      _vocabulary.roleOf(fragment) == null;
}

enum _Band { header, body, footer }
