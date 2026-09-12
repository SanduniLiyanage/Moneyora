/// Formatting for money.
///
/// Amounts live as **integer minor units** everywhere else in the app — cents
/// for LKR, and for every other currency this project is likely to meet
/// (E-06). This is the one file allowed to turn them into something a person
/// reads, which is what keeps `double` out of the rest of the codebase.
///
/// The reason is not fussiness. `0.1 + 0.2 != 0.3` in IEEE-754, so a balance
/// accumulated as `double` drifts from the sum of the transactions that
/// produced it — slowly, invisibly, and in a finance app.
library;

/// Currency display rules.
///
/// Only LKR is needed today (SRS §2.3), but FR-ACC-005 requires multi-currency
/// accounts, so the shape allows for more rather than hard-coding "Rs".
class CurrencyFormat {
  /// Creates a format.
  const CurrencyFormat({
    required this.code,
    required this.symbol,
    this.decimalDigits = 2,
  });

  /// ISO 4217 code, e.g. `LKR`.
  final String code;

  /// What precedes the amount, e.g. `Rs`.
  final String symbol;

  /// Minor units per major unit, as a power of ten. Two for LKR.
  final int decimalDigits;

  /// Sri Lankan rupee — the default (SRS §2.3).
  static const CurrencyFormat lkr = CurrencyFormat(code: 'LKR', symbol: 'Rs');

  /// Display rules for [code], falling back to the code itself as the symbol.
  ///
  /// LKR is the only currency with a real symbol here, because it is the only
  /// one the app can do arithmetic in until FR-ACC-005 lands (deferred to
  /// Sprint 7 by E-25). An account held in dollars therefore renders as
  /// `USD 1,234.56` rather than borrowing `Rs`, which would state something
  /// false about money the app cannot convert.
  ///
  /// A symbol table arrives with conversion. Guessing `$` for USD now would
  /// mean guessing it for a dozen others, and `$` is ambiguous across at
  /// least five currencies before you reach the hard cases.
  static CurrencyFormat forCode(String code) {
    final normalised = code.trim().toUpperCase();
    if (normalised == lkr.code) return lkr;
    return CurrencyFormat(code: normalised, symbol: '$normalised ');
  }

  /// How many minor units make one major unit.
  int get minorUnitsPerMajor => switch (decimalDigits) {
    0 => 1,
    1 => 10,
    2 => 100,
    3 => 1000,
    _ => throw ArgumentError('Unsupported decimalDigits: $decimalDigits'),
  };
}

/// Turns minor units into a display string.
///
/// ```dart
/// formatCents(123456)                  // 'Rs1,234.56'
/// formatCents(-50000)                  // '-Rs500.00'
/// formatCents(123456, showSymbol: false) // '1,234.56'
/// ```
///
/// Grouping is applied to the whole part with commas, which is the convention
/// in Sri Lanka and matches how the reference app renders amounts.
///
/// A negative sign goes **before** the symbol (`-Rs500.00`) rather than after
/// it, because `Rs-500.00` reads as a typo.
String formatCents(
  int cents, {
  CurrencyFormat currency = CurrencyFormat.lkr,
  bool showSymbol = true,
}) {
  final negative = cents < 0;
  final absolute = cents.abs();
  final divisor = currency.minorUnitsPerMajor;

  final whole = absolute ~/ divisor;
  final fraction = absolute % divisor;

  final buffer = StringBuffer()
    ..write(negative ? '-' : '')
    ..write(showSymbol ? currency.symbol : '')
    ..write(_groupThousands(whole));

  if (currency.decimalDigits > 0) {
    buffer
      ..write('.')
      ..write(fraction.toString().padLeft(currency.decimalDigits, '0'));
  }
  return buffer.toString();
}

/// Turns minor units into the short form an axis tick has room for.
///
/// ```dart
/// formatCentsCompact(0)           // 'Rs0'
/// formatCentsCompact(85000)       // 'Rs850'
/// formatCentsCompact(123456)      // 'Rs1.2k'
/// formatCentsCompact(5000000)     // 'Rs50k'
/// formatCentsCompact(150000000)   // 'Rs1.5M'
/// ```
///
/// For chart axes only (FR-RPT-005): a tick reading `Rs50,000.00` is wider
/// than the plot beside it. Everywhere a person reads an *amount* rather
/// than a scale, [formatCents] applies — this never rounds anything a user
/// is owed or owes, only the labels on a ruler. Integer arithmetic
/// throughout; the one decimal place is a remainder, not a `double`.
String formatCentsCompact(
  int cents, {
  CurrencyFormat currency = CurrencyFormat.lkr,
}) {
  final negative = cents < 0;
  final whole = cents.abs() ~/ currency.minorUnitsPerMajor;

  final (scaled, tenths, suffix) = switch (whole) {
    >= 1000000 => (whole ~/ 1000000, (whole % 1000000) ~/ 100000, 'M'),
    >= 1000 => (whole ~/ 1000, (whole % 1000) ~/ 100, 'k'),
    _ => (whole, 0, ''),
  };

  final buffer = StringBuffer()
    ..write(negative ? '-' : '')
    ..write(currency.symbol)
    ..write(scaled);
  // One decimal only while it changes the reading: `Rs1.2k` earns its digit,
  // `Rs50.0k` does not — and past ten of a unit the tenth is noise.
  if (tenths > 0 && scaled < 10) buffer.write('.$tenths');
  buffer.write(suffix);
  return buffer.toString();
}

/// Parses user input into minor units.
///
/// Returns `null` when the text is not a number, so callers decide what to do
/// rather than being handed a silent zero — an unparseable amount that becomes
/// `0` is a transaction that looks saved and is wrong.
///
/// Accepts grouping separators and an optional symbol, because people paste
/// things like `Rs 1,234.56`.
int? parseToCents(
  String input, {
  CurrencyFormat currency = CurrencyFormat.lkr,
}) {
  final cleaned = input
      .replaceAll(currency.symbol, '')
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .trim();
  if (cleaned.isEmpty) return null;

  final value = double.tryParse(cleaned);
  if (value == null) return null;

  // double only appears here, on the boundary, and is rounded away
  // immediately. Anything past this line is an int.
  return (value * currency.minorUnitsPerMajor).round();
}

/// Inserts thousands separators: `1234567` -> `1,234,567`.
String _groupThousands(int value) {
  final digits = value.toString();
  if (digits.length <= 3) return digits;

  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    // A separator goes before every digit whose distance from the end is a
    // multiple of three, except at position zero.
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
