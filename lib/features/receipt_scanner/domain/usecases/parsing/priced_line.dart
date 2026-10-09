import '../../entities/receipt_line_item.dart';

/// A line that ends in a money figure, split into the figure and the words
/// before it. FR-RCP-005, FR-RCP-006.
///
/// The one place a receipt's figures are read, so every stage agrees on
/// what a price is:
/// - **Amounts are integer cents from the printed digits** (E-06). `Rs`,
///   `LKR` and a trailing `/-` are ignored, a thousands comma is stripped,
///   and the decimal separator is a dot.
/// - **A figure misread by the camera is mended first.** A photo is read
///   with a comma for the point (`240,00`), a gap beside it (`240. 00`), or
///   a letter for a digit (`18O.OO`). Only a figure that ends the line with
///   two decimals is mended, so a thousands comma, a date and a time are
///   left as printed.
/// - **The figure with the decimals is the price.** `2 x 240.00` is a count
///   then a price; `2790.00 X 1` is a price then a count, as boutiques
///   print it.
/// - **A row number and an article code are not the name.** `1 126285
///   SAFEGUARD SOAP` is row 1, code 126285, the soap; the number and the
///   code are kept, because a discount line names its item by them.
/// - **A code row is an item's figures without its name.** Some tills print
///   the name on one line and `SCE0833 1.000 50.00 50.00` beneath it — an
///   article code (letters, then digits), the quantity, the price, the
///   amount. Such a row is [isCodeRow]; the body reader names it with the
///   line above.
class PricedLine {
  const PricedLine._({
    required this.line,
    required this.rest,
    required this.cents,
    required this.hasCents,
  });

  /// The line with its figure mended, or null when no figure ends it.
  static PricedLine? of(String printed) {
    final line = _mended(collapse(printed));
    final m = _trailing.firstMatch(line);
    if (m == null) return null;
    return PricedLine._(
      line: line,
      rest: line.substring(0, m.start).trim(),
      cents: centsOf(m[2]!, m[3], negative: m[1] != null),
      hasCents: m[3] != null,
    );
  }

  /// Whitespace collapsed to single spaces, ends trimmed.
  static String collapse(String line) =>
      line.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// The whole line, as mended.
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
    '(?:^|[\\s:=])$_currency\\s*([-–—])?\\s*$_figure\\s*(?:/[-=])?\\s*\$',
    caseSensitive: false,
  );

  /// `2 x 240.00`, `2 @ 240.00`, `1.5 kg x 320.00` at the end of [rest].
  static final _qtyByUnit = RegExp(
    '(\\d+(?:\\.\\d+)?)\\s*(?:kg|g|l|ml|pcs?)?\\s*[x×@*]\\s*$_currency\\s*'
    '$_figure\\s*=?\\s*\$',
    caseSensitive: false,
  );

  /// `1.0 350.00`, `0.350 1,200.00` at the end of [rest]: a quantity column
  /// then a price column, with no `x` between — the line amount after them
  /// is what decides whether they are that (see [toItem]).
  static final _qtyThenPrice = RegExp(
    r'(?:^|\s)(\d{1,3}(?:\.\d{1,3})?)\s+(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})$',
  );

  /// `0.01 X` at the end of [rest]: a unit price whose count OCR lost.
  static final _priceByLostQty = RegExp(
    '$_currency\\s*$_figure\\s*[x×@*]\\s*\$',
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

  /// A comma for the point, or a gap beside it, before the two decimals
  /// that end the line: `240,00`, `240. 00`, `240 .00`. Two digits, never
  /// three, so `1,250` keeps its thousands comma.
  static final _brokenPoint = RegExp(r'(\d) ?[.,] ?(\d{2})(\s*/[-=])?$');

  /// A figure ending the line with two decimals and a letter or two among
  /// its digits — `18O.OO`, `l80,00`, `S99.60` — not run on from a word.
  static final _lettersInFigure = RegExp(
    r'(?<![A-Za-z\d])([\dOoIlS][\dOoIlS,]*[.,][\dOoIlS]{2})(\s*/[-=])?$',
  );

  static String _mended(String line) {
    var mended = line;
    if (_lettersInFigure.firstMatch(mended) case final m?
        when m[1]!.contains(RegExp(r'\d'))) {
      final digits = m[1]!
          .replaceAll(RegExp('[Oo]'), '0')
          .replaceAll(RegExp('[Il]'), '1')
          .replaceAll('S', '5');
      mended = mended.replaceRange(m.start, m.start + m[1]!.length, digits);
    }
    return mended.replaceFirstMapped(
      _brokenPoint,
      (m) => '${m[1]}.${m[2]}${m[3] ?? ''}',
    );
  }

  /// A row number (`01 `, `2. `) and article codes (`126285 `) at the
  /// start; group 1 is the row, group 2 the codes.
  static final _leadingCodes = RegExp(
    r'^(?:(\d{1,2})[.)]?\s+)?((?:\d{4,}\s+)*)',
  );

  /// `25.20%` anywhere in [rest].
  static final _percent = RegExp(r'(\d{1,3}(?:\.\d{1,2})?)\s*%');

  /// A figure as OCR may print one in a column: digits with `O` for 0,
  /// `l` or `I` for 1, a bracket for a lost leading 0, a comma for a point.
  static const _columnFigure = r'[\d)(\[\]OoIl|.,]*\d[\d)(\[\]OoIl|.,]*';

  /// `SCE0833 1.000 50.00` as [rest]: an optional row number, an article
  /// code — up to four letters, then digits, OCR's O and l among them —
  /// and up to two figures. Group 2 is the code, group 3 the figures.
  static final _codeRow = RegExp(
    '^(?:(\\d{1,2})[.)]?\\s+)?([A-Z]{1,4}[0-9OIl]{3,}[A-Z0-9]*)'
    '((?:\\s+$_columnFigure){0,2})\$',
    caseSensitive: false,
  );

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

  /// The row number printed at the start, when one is.
  int? get rowNumber => switch (_leadingCodes.firstMatch(rest)?[1]) {
    final n? => int.parse(n),
    null => null,
  };

  /// The first article code printed at the start, when one is — the
  /// letters-and-digits code of a code row included.
  String? get code {
    if (_codeRowMatch case final m?) return m[2];
    final codes = _leadingCodes.firstMatch(rest)?[2]?.trim();
    if (codes == null || codes.isEmpty) return null;
    return codes.split(' ').first;
  }

  /// True when the line is an item's code and figures with no name: see
  /// the class's notes.
  bool get isCodeRow => _codeRowMatch != null;

  RegExpMatch? get _codeRowMatch {
    final m = _codeRow.firstMatch(rest);
    // Two digits at least, so `ABC1` or `KG500` in a name is not a code.
    if (m == null || RegExp(r'\d').allMatches(m[2]!).length < 3) return null;
    return m;
  }

  /// [token] as a plain number — `).160` → `0.160`, `1,56O.00` →
  /// `1560.00`, `120,00` → `120.00`, `1.560.00` → `1560.00` — or null
  /// when it is no number at all.
  static String? columnNumber(String token) {
    var t = token
        .replaceAll(RegExp('[Oo]'), '0')
        .replaceAll(RegExp(r'[Il|]'), '1')
        .replaceFirst(RegExp(r'^[)(\[\]]+(?=\.)'), '0')
        .replaceFirst(RegExp(r'^[)(\[\]]+'), '')
        .replaceFirstMapped(RegExp(r',(\d{2})$'), (m) => '.${m[1]}')
        .replaceAll(',', '');
    final points = '.'.allMatches(t).length;
    if (points > 1) {
      final last = t.lastIndexOf('.');
      t = t.substring(0, last).replaceAll('.', '') + t.substring(last);
    }
    return RegExp(r'^\d+(?:\.\d+)?$').hasMatch(t) ? t : null;
  }

  /// The quantity [token] stands for, given a unit price of [unitCents]
  /// and this line's amount — the amount is the truth.
  ///
  /// As read when it multiplies out to the amount, to the cent a weight's
  /// rounding allows. Otherwise the quantity the amount implies, when it
  /// has at most three decimals and OCR printed its digits with the point
  /// lost or moved: `1000` for 1.000, `0160` for 0.160. Null when neither.
  double? quantityFor(String token, int unitCents) {
    if (unitCents <= 0) return null;
    final read = double.tryParse(token);
    if (read != null && read > 0 && _multipliesOutTo(read, unitCents)) {
      return read;
    }
    final thousandths = (cents * 1000 / unitCents).round();
    if (thousandths <= 0 || !_multipliesOutTo(thousandths / 1000, unitCents)) {
      return null;
    }
    String digits(String s) => s
        .replaceAll('.', '')
        .replaceFirst(RegExp('^0+'), '')
        .replaceFirst(RegExp(r'0+$'), '');
    return digits(token) == digits('$thousandths') ? thousandths / 1000 : null;
  }

  bool _multipliesOutTo(double quantity, int unitCents) =>
      ((quantity * unitCents).round() - cents).abs() <= 1;

  /// The percentage printed on the line — a discount's rate — or null.
  double? get percent => switch (_percent.firstMatch(rest)?[1]) {
    final p? => double.parse(p),
    null => null,
  };

  /// [name] without its leading row number and article codes, unless that
  /// would leave nothing.
  static String withoutLeadingCodes(String name) {
    final stripped = name.replaceFirst(_leadingCodes, '').trim();
    return stripped.isEmpty ? name : stripped;
  }

  /// The item this line describes, or null when no name survives.
  ///
  /// **The line amount is the truth.** A count and a unit price printed
  /// before it are read, and a quantity column then a price column (`1.0
  /// 350.00 350.00`) is taken as one only when the two multiply out to
  /// the amount — otherwise those figures are part of the name, as
  /// printed, rather than a quantity the receipt never meant.
  ReceiptLineItem? toItem() {
    if (_codeRowMatch case final m?) return _codeRowItem(m);
    var name = rest;
    var quantity = 1.0;
    int? unit;

    if (_qtyByUnit.firstMatch(name) case final m?) {
      final first = m[1]!;
      if (first.contains('.') && m[3] == null) {
        // `2790.00 X 1`: the price, then the count.
        final parts = first.split('.');
        unit = centsOf(parts[0], parts[1]);
        quantity = double.parse(m[2]!.replaceAll(',', ''));
      } else {
        quantity = double.parse(first);
        unit = centsOf(m[2]!, m[3]);
      }
      name = name.substring(0, m.start);
    } else if (_priceByLostQty.firstMatch(name) case final m?
        when m[2] != null) {
      final price = centsOf(m[1]!, m[2]);
      if (price > 0 && cents % price == 0) {
        unit = price;
        quantity = (cents ~/ price).toDouble();
      }
      name = name.substring(0, m.start);
    } else if (_qtyThenPrice.firstMatch(name) case final m?
        when _multipliesOut(m[1]!, centsOf(m[2]!, m[3]))) {
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
    name = withoutLeadingCodes(name);
    if (name.isEmpty) return null;
    return ReceiptLineItem(
      name: name,
      quantity: quantity,
      unitPriceCents: unit,
      totalPriceCents: cents,
    );
  }

  /// True when [quantity] of [unitCents] is this line's amount, to the
  /// cent a weighed item's rounding allows.
  bool _multipliesOut(String quantity, int unitCents) {
    final count = double.parse(quantity);
    if (count <= 0 || unitCents <= 0) return false;
    return _multipliesOutTo(count, unitCents);
  }

  /// A code row as an item named by its code, until the body reader names
  /// it with the line above. Its two figures are the quantity and the
  /// price when [quantityFor] can make the amount of them, and are dropped
  /// either way: they are columns, not part of a name.
  ReceiptLineItem _codeRowItem(RegExpMatch row) {
    final figures = row[3]!.trim().split(RegExp(r'\s+'))
      ..removeWhere((f) => f.isEmpty);
    var quantity = 1.0;
    int? unit;
    if (figures.length == 2) {
      final price = columnNumber(figures[1]);
      final count = columnNumber(figures[0]);
      if (price != null && count != null) {
        final parts = price.split('.');
        final priceCents = centsOf(
          parts[0],
          parts.length > 1 ? parts[1] : null,
        );
        if (quantityFor(count, priceCents) case final q?) {
          quantity = q;
          unit = priceCents;
        }
      }
    }
    return ReceiptLineItem(
      name: row[2]!,
      quantity: quantity,
      unitPriceCents: unit,
      totalPriceCents: cents,
    );
  }
}
