import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/parsed_receipt.dart';
import '../entities/receipt_line_item.dart';
import '../entities/recognised_text.dart';

/// Merchant, date, line items, total, tax and receipt number, from the
/// lines OCR read. FR-RCP-005, FR-RCP-006, E-31.
///
/// The fourth stage of the pipeline (SDD §7.2): after ML Kit, before the
/// categoriser. Pure text — nothing here knows an image existed, which is
/// what lets a test state a receipt as a string.
///
/// A receipt is read as three bands. The **header** runs from the first
/// line to the first priced line: its first line of words that is not a
/// date, a phone number, an address or a receipt number is the merchant.
/// The **body** runs from there to the total line: every priced line in it
/// is an item unless its label says otherwise (a discount, a sub-total, a
/// count, the cash tendered). The **footer** is everything after the total:
/// change, card, the VAT breakdown, "thank you" — priced, and never items.
///
/// Decisions the SRS does not make:
/// - **Amounts are integer cents converted from the printed digits**, with
///   no floating point on the way (E-06). `Rs`, `LKR` and a trailing `/-`
///   are accepted and ignored, a thousands comma is stripped, and the
///   decimal separator is a dot.
/// - **A price is a figure at the end of a line.** The first item is the
///   first line whose figure prints cents, or a `2 x 240.00` quantity — a
///   header line that merely ends in digits (`COLOMBO 03`) is not a price.
///   Inside the body, whole-rupee figures are prices.
/// - **Dates are day-first.** `03/04/2026` is 3 April: Sri Lankan receipts
///   print `dd/mm/yyyy`, and the ISO form is unambiguous either way. A
///   two-digit year is this century; the first date found is the one kept.
/// - **The total is the *last* total-labelled line**, because a receipt
///   prints its sub-total before its total, never after. "Sub total",
///   "total items", "total qty", "total discount" and "total VAT" are not
///   totals.
/// - **The tax figure is the *first* tax-labelled line** — a receipt that
///   breaks VAT down by rate repeats the figure, and summing would double
///   it. `VAT NO` and `TIN` are registration numbers, not figures.
/// - **A line of words with no price joins the priced line beneath it**
///   when that line has no words of its own. ML Kit reads a two-line item
///   — the name, then `2 x 240.00  480.00` — as two lines, and nothing else
///   on a receipt has that shape. A priced line with its own words drops
///   the words above it: those were a heading, not a name.
/// - **The merchant line never joins.** A receipt with no merchant printed
///   reads its first item's name as the merchant; FR-RCP-008's review
///   screen is where that is corrected, and guessing further here would
///   mis-name real merchants to fix an unusual receipt.
/// - **Negative lines are not items.** A discount subtracts from the
///   total; FR-RCP-009 makes an expense of every item.
/// - **A unit price is stated or exact.** Read from `qty x price` when
///   printed; derived as `total ÷ qty` only when the division is exact;
///   null otherwise, rather than a rounded figure the receipt never showed.
///
/// Nothing here is a claim about accuracy. The fixtures in the test are
/// hand-written to the shapes above; the ROADMAP's 20–30 real photos are
/// the only basis for a figure, and collecting them is Sprint 6's first
/// week. ML Kit's line order is taken as printed order.
class ParseReceiptText implements UseCase<ParsedReceipt, RecognisedText> {
  /// Creates the parser. Stateless.
  const ParseReceiptText();

  @override
  Future<Either<Failure, ParsedReceipt>> call(RecognisedText params) async {
    final receipt = parse(params);
    if (receipt.items.isEmpty && receipt.totalCents == null) {
      return const Left(OcrFailure());
    }
    return Right(receipt);
  }

  /// Parses [text], returning whatever was found — possibly nothing.
  ///
  /// Static so a test can state the rules without the failure wrapper.
  static ParsedReceipt parse(RecognisedText text) {
    String? merchant;
    DateTime? date;
    String? receiptNumber;
    int? total;
    int? tax;
    final items = <ReceiptLineItem>[];

    var band = _Band.header;
    // The most recent line of words that carried no price; the name of a
    // two-line item until a priced line says otherwise.
    String? pendingWords;

    for (final raw in text.lines) {
      final line = _collapse(raw);
      if (line.isEmpty) continue;

      if (date == null) {
        date = _dateOf(line);
        if (date != null) {
          receiptNumber ??= _receiptNumberOf(line);
          pendingWords = null;
          continue;
        }
      }
      if (receiptNumber == null) {
        receiptNumber = _receiptNumberOf(line);
        if (receiptNumber != null) {
          pendingWords = null;
          continue;
        }
      }
      if (_noise.hasMatch(line) ||
          (band == _Band.header && _headerNoise.hasMatch(line))) {
        pendingWords = null;
        continue;
      }

      final priced = _Priced.of(line);
      if (priced == null) {
        if (band == _Band.header && merchant == null) {
          merchant = line;
        } else {
          pendingWords = line;
        }
        continue;
      }

      // A wordless priced line completes the words above it.
      final effective = priced.isWordless && pendingWords != null
          ? _Priced.of('$pendingWords ${priced.line}')!
          : priced;
      pendingWords = null;

      if (_totalLabel.hasMatch(effective.rest) &&
          !_notTotalLabel.hasMatch(effective.rest)) {
        total = effective.cents;
        band = _Band.footer;
        continue;
      }
      if (_taxLabel.hasMatch(effective.rest)) {
        tax ??= effective.cents;
        continue;
      }
      if (band == _Band.footer ||
          effective.cents < 0 ||
          _bodyNoise.hasMatch(effective.rest)) {
        continue;
      }
      if (band == _Band.header && !effective.startsBody) continue;

      band = _Band.body;
      final item = effective.toItem();
      if (item != null) items.add(item);
    }

    return ParsedReceipt(
      merchantName: merchant,
      receiptDate: date,
      items: items,
      totalCents: total,
      taxCents: tax,
      receiptNumber: receiptNumber,
    );
  }

  /// Whitespace collapsed to single spaces, ends trimmed.
  static String _collapse(String line) =>
      line.replaceAll(RegExp(r'\s+'), ' ').trim();

  // -- Dates --------------------------------------------------------------

  static final _numericDate = RegExp(
    r'(?<!\d)(\d{1,2})[/.-](\d{1,2})[/.-](\d{4}|\d{2})(?!\d)',
  );
  static final _isoDate = RegExp(r'(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)');
  static final _wordDate = RegExp(
    r'(?<!\d)(\d{1,2})[\s.-]*'
    r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*'
    r'[\s.,-]*(\d{4}|\d{2})(?!\d)',
    caseSensitive: false,
  );
  static final _time = RegExp(
    r'(?<!\d)(\d{1,2}):(\d{2})(?::\d{2})?\s*(am|pm)?(?![\d:])',
    caseSensitive: false,
  );
  static const _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// The date on [line], with its time when one follows, or null.
  static DateTime? _dateOf(String line) {
    int year, month, day;
    if (_isoDate.firstMatch(line) case final m?) {
      year = int.parse(m[1]!);
      month = int.parse(m[2]!);
      day = int.parse(m[3]!);
    } else if (_numericDate.firstMatch(line) case final m?) {
      day = int.parse(m[1]!);
      month = int.parse(m[2]!);
      year = _fourDigit(m[3]!);
    } else if (_wordDate.firstMatch(line) case final m?) {
      day = int.parse(m[1]!);
      month = _months.indexOf(m[2]!.toLowerCase()) + 1;
      year = _fourDigit(m[3]!);
    } else {
      return null;
    }

    var hour = 0, minute = 0;
    if (_time.firstMatch(line) case final t?) {
      hour = int.parse(t[1]!);
      minute = int.parse(t[2]!);
      final meridiem = t[3]?.toLowerCase();
      if (meridiem == 'pm' && hour < 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;
      if (hour > 23 || minute > 59) hour = minute = 0;
    }

    final date = DateTime(year, month, day, hour, minute);
    // DateTime normalises 31/02 into March; a printed date must not.
    if (date.month != month || date.day != day) return null;
    return date;
  }

  static int _fourDigit(String year) =>
      year.length == 4 ? int.parse(year) : 2000 + int.parse(year);

  // -- Receipt number -----------------------------------------------------

  /// `Receipt No: 4521`, `INV# A-0042`, `Bill 000123`. The token must hold
  /// a digit, so `INVOICE TOTAL` captures nothing.
  static final _receiptNumber = RegExp(
    r'\b(?:receipt|invoice|inv|bill|rcpt|txn|trans(?:action)?)\s*'
    r'(?:no|number|num|id|#)?\.?\s*[:#-]?\s*'
    r'((?=[A-Z0-9/-]*\d)[A-Z0-9][A-Z0-9/-]*)',
    caseSensitive: false,
  );

  static String? _receiptNumberOf(String line) =>
      _receiptNumber.firstMatch(line)?[1];

  // -- Labels -------------------------------------------------------------

  /// Lines that are never items or headers, in any band.
  static final _noise = RegExp(
    r'\b(?:tel|phone|fax|mobile|hotline|cashier|served by|www|e-?mail)\b'
    r'|[a-z0-9._-]+@[a-z0-9-]+\.[a-z]|\.com\b|\.lk\b'
    r'|\b(?:vat|tin|tax|svat)\s*(?:reg(?:istration)?|no|number|#|id)\b'
    r'|\bthank',
    caseSensitive: false,
  );

  /// Address, table and document-title lines, which sit above the first
  /// item. `TAX INVOICE` on its own line is a title, not a merchant.
  static final _headerNoise = RegExp(
    r'^(?:tax\s+)?(?:invoice|receipt|bill|cash\s+(?:bill|memo))$'
    r'|\b(?:road|rd|street|st|lane|avenue|ave|mawatha|mw|place|colombo)\b'
    r'|\bno\.?\s*\d'
    r'|\b(?:table|counter|terminal|pos|pax|guests?|covers?)\b',
    caseSensitive: false,
  );

  static final _totalLabel = RegExp(
    r'\btotal\b|\bamount due\b|\bnet amount\b|\bbalance due\b',
    caseSensitive: false,
  );
  static final _notTotalLabel = RegExp(
    r'sub\s*-?\s*total'
    r'|total\s*(?:items?|qty|quantity|pcs|discount|savings?|vat|tax)\b',
    caseSensitive: false,
  );
  static final _taxLabel = RegExp(
    r'\b(?:vat|tax|gst|sscl|nbt)\b',
    caseSensitive: false,
  );

  /// Priced lines in the body that are not items: payment lines, the
  /// sub-total and its kin, and a count of items — which is a line that
  /// *starts* with the count label, so `EGGS 10 PCS` stays an item.
  static final _bodyNoise = RegExp(
    r'\b(?:cash|change|tender(?:ed)?|card|visa|master(?:card)?|amex|paid|'
    r'payment|balance|discount|round(?:ing)?)\b'
    r'|sub\s*-?\s*total'
    r'|\btotal\s*(?:items?|qty|quantity|pcs|discount|savings?)\b'
    r'|^(?:no\.?\s*of\s*)?(?:qty|quantity|items?|pcs|pieces)\b',
    caseSensitive: false,
  );
}

enum _Band { header, body, footer }

/// A line that ends in a money figure, split into the figure and the rest.
class _Priced {
  const _Priced._({
    required this.line,
    required this.rest,
    required this.cents,
    required this.hasCents,
  });

  /// The whole line, as collapsed.
  final String line;

  /// The line with the figure stripped.
  final String rest;

  /// The figure, minor units, negative when a minus sign preceded it.
  final int cents;

  /// True when the figure printed a decimal part.
  final bool hasCents;

  /// Digits with thousands commas, an optional one- or two-digit fraction.
  static const _figure = r'(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?';
  static const _currency = r'(?:rs\.?|lkr)?';

  static final _trailing = RegExp(
    '(?:^|[\\s:=])$_currency\\s*(-)?\\s*$_figure\\s*(?:/[-=])?\\s*\$',
    caseSensitive: false,
  );

  /// `2 x 240.00`, `2 @ 240.00`, `1.5 kg x 320.00` at the end of [rest].
  static final _qtyByUnit = RegExp(
    '(\\d+(?:\\.\\d+)?)\\s*(?:kg|g|l|ml|pcs?)?\\s*[x×@*]\\s*$_currency\\s*'
    '$_figure\\s*=?\\s*\$',
    caseSensitive: false,
  );

  /// `2 x MILK` at the start of [rest].
  static final _leadingQty = RegExp(
    r'^(\d+(?:\.\d+)?)\s*[x×]\s*(?=[a-z])',
    caseSensitive: false,
  );

  /// `MILK x2`, `MILK qty 2`, `EGGS 10 PCS` at the end of [rest] — an
  /// integer only, so `x 240.00` (a price) is never read as a count.
  static final _trailingQty = RegExp(
    r'\s+(?:(?:[x×]|qty\.?:?)\s*(\d+)|(\d+)\s*(?:pcs|pieces|nos))$',
    caseSensitive: false,
  );

  /// Anything that is not a word once currency marks are removed.
  static final _wordless = RegExp(r'^[\d\s.,x×@*:=/-]*$', caseSensitive: false);
  static final _currencyMark = RegExp(
    r'\b(?:rs\.?|lkr)\b',
    caseSensitive: false,
  );

  static _Priced? of(String line) {
    final m = _trailing.firstMatch(line);
    if (m == null) return null;
    final cents = centsOf(m[2]!, m[3], negative: m[1] != null);
    return _Priced._(
      line: line,
      rest: line.substring(0, m.start).trim(),
      cents: cents,
      hasCents: m[3] != null,
    );
  }

  /// [integer] and [fraction] as printed, to minor units, in integers.
  static int centsOf(
    String integer,
    String? fraction, {
    bool negative = false,
  }) {
    final whole = int.parse(integer.replaceAll(',', ''));
    final cents =
        whole * 100 +
        (fraction == null ? 0 : int.parse(fraction.padRight(2, '0')));
    return negative ? -cents : cents;
  }

  /// True when nothing but figures and quantity marks precede the price.
  bool get isWordless => _wordless.hasMatch(rest.replaceAll(_currencyMark, ''));

  /// True when this line can be the first item: a price with cents, or a
  /// quantity multiplied out.
  bool get startsBody => hasCents || _qtyByUnit.hasMatch(rest);

  /// The item this line describes, or null when no name survives.
  ReceiptLineItem? toItem() {
    var name = rest;
    var quantity = 1.0;
    int? unit;

    if (_qtyByUnit.firstMatch(name) case final m?) {
      quantity = double.parse(m[1]!);
      unit = centsOf(m[2]!, m[3]);
      name = name.substring(0, m.start);
    } else if (_trailingQty.firstMatch(name) case final m?) {
      quantity = double.parse((m[1] ?? m[2])!);
      name = name.substring(0, m.start);
    } else if (_leadingQty.firstMatch(name) case final m?) {
      quantity = double.parse(m[1]!);
      name = name.substring(m.end);
    }

    if (unit == null && quantity > 1 && quantity == quantity.roundToDouble()) {
      final count = quantity.round();
      if (cents % count == 0) unit = cents ~/ count;
    }

    name = name.replaceAll(RegExp(r'[\s:=.\-]+$'), '').trim();
    if (name.isEmpty) return null;
    return ReceiptLineItem(
      name: name,
      quantity: quantity,
      unitPriceCents: unit,
      totalPriceCents: cents,
    );
  }
}
