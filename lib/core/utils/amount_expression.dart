/// The arithmetic behind the entry screen's custom keypad. FR-EXP-002.
///
/// Pure Dart, with no Flutter in sight, so the rules can be tested in
/// milliseconds instead of driven through a widget. The keypad widget owns
/// only the buttons; every decision about what a keypress *means* is here.
///
/// ## Why a calculator at all
///
/// People do not arrive at a number, they arrive at a receipt: 1,250 for the
/// groceries plus 340 for the bus. Making them add that up elsewhere and type
/// the total is the difference between logging a purchase and giving up.
///
/// ## Money stays an integer
///
/// Everything below works in minor units. `double` appears nowhere — not even
/// briefly — because the whole point of `amount_cents` is that no value in the
/// app ever passes through a representation that cannot hold 0.10 exactly.
library;

import 'currency_utils.dart';

/// An operation the keypad can apply.
enum AmountOperator {
  /// Adding two amounts, the common case: several items on one receipt.
  add('+'),

  /// Subtracting, usually a discount or a returned item.
  subtract('−'),

  /// Multiplying an amount by a count — four coffees at 350.
  multiply('×'),

  /// Dividing an amount by a count — a bill split three ways.
  divide('÷');

  const AmountOperator(this.symbol);

  /// What the key shows. The proper minus and times signs, not `-` and `x`.
  final String symbol;
}

/// What the user has keyed in so far.
///
/// Immutable: every keypress returns a new expression, which makes the state
/// trivially testable and means an undo is just holding the previous value.
///
/// Evaluation is strictly **left to right**, with no operator precedence. That
/// is deliberate. The keypad shows a running result as soon as a second
/// operator is pressed, and under precedence rules that running number would
/// be a lie — `100 + 20 × 3` would display `120` and then silently become
/// `160`. A pocket calculator behaves this way for the same reason.
class AmountExpression {
  /// Creates an expression from its parts. Prefer [AmountExpression.empty].
  const AmountExpression({
    this.accumulatedCents,
    this.pendingOperator,
    this.entry = '',
  });

  /// A blank keypad.
  factory AmountExpression.empty() => const AmountExpression();

  /// The running total of everything before [pendingOperator].
  ///
  /// Null until an operator has been pressed.
  final int? accumulatedCents;

  /// The operator waiting for a right-hand side.
  final AmountOperator? pendingOperator;

  /// The digits typed since the last operator, as text.
  ///
  /// Kept as text rather than a number so that `1.` and `1.0` are different
  /// things on screen — a number would erase the decimal point the moment it
  /// was typed and the user would never get to key the digits after it.
  final String entry;

  /// The amount currently being typed, in minor units. Null when [entry] is
  /// empty or is a lone decimal point.
  int? get entryCents => entry.isEmpty ? null : parseToCents(entry);

  /// True when nothing has been keyed at all.
  bool get isEmpty =>
      entry.isEmpty && accumulatedCents == null && pendingOperator == null;

  /// The value this expression evaluates to, or null if it cannot be resolved.
  ///
  /// Null covers two cases a screen must handle: nothing typed yet, and a
  /// division by zero. Neither is an error worth an error message — the Save
  /// button simply stays disabled.
  int? get valueCents {
    final typed = entryCents;

    if (pendingOperator == null) return typed ?? accumulatedCents;
    if (typed == null) return accumulatedCents;

    return _apply(accumulatedCents ?? 0, pendingOperator!, typed);
  }

  /// What the display shows.
  String get display {
    if (isEmpty) return '0';
    if (pendingOperator == null) return entry.isEmpty ? '0' : entry;

    final left = formatCents(accumulatedCents ?? 0, showSymbol: false);
    return '$left ${pendingOperator!.symbol} $entry'.trimRight();
  }

  /// Appends a digit.
  AmountExpression digit(String value) {
    assert(value.length == 1 && '0123456789'.contains(value), 'one digit');

    // Two decimal places is all LKR has, and letting a third be typed only to
    // round it away at save time is a small lie the user notices later.
    if (_decimalsTyped >= CurrencyFormat.lkr.decimalDigits) return this;

    // A single leading zero is replaced rather than extended, so keying 0
    // then 5 gives 5 and not 05.
    final next = entry == '0' ? value : '$entry$value';
    return _withEntry(next);
  }

  /// Appends a decimal point, if one is not already present.
  AmountExpression decimalPoint() {
    if (entry.contains('.')) return this;
    return _withEntry(entry.isEmpty ? '0.' : '$entry.');
  }

  /// Applies [operator], folding whatever is typed into the running total.
  ///
  /// Pressing a second operator without typing anything replaces the first,
  /// which is what a user who mis-hit `+` instead of `−` expects.
  AmountExpression operation(AmountOperator operator) {
    if (entry.isEmpty) {
      if (accumulatedCents == null) return this;
      return AmountExpression(
        accumulatedCents: accumulatedCents,
        pendingOperator: operator,
      );
    }

    final resolved = valueCents;
    if (resolved == null) return this;

    return AmountExpression(
      accumulatedCents: resolved,
      pendingOperator: operator,
    );
  }

  /// Collapses the expression to its result, as the `=` key does.
  AmountExpression evaluated() {
    final resolved = valueCents;
    if (resolved == null) return this;
    return AmountExpression(entry: _plainText(resolved));
  }

  /// Removes the last keystroke.
  AmountExpression backspace() {
    if (entry.isNotEmpty) {
      return _withEntry(entry.substring(0, entry.length - 1));
    }
    if (pendingOperator != null) {
      // Put the running total back into the entry rather than leaving it in
      // `accumulatedCents` with no operator. Stranded there it would still
      // count towards `valueCents` while the display showed nothing — the two
      // must never disagree, because the number on screen is the one the user
      // is about to save.
      return AmountExpression(
        entry: accumulatedCents == null ? '' : _plainText(accumulatedCents!),
      );
    }
    return AmountExpression.empty();
  }

  /// Clears everything.
  AmountExpression cleared() => AmountExpression.empty();

  AmountExpression _withEntry(String value) => AmountExpression(
    accumulatedCents: accumulatedCents,
    pendingOperator: pendingOperator,
    entry: value,
  );

  /// An amount as bare keyable text — no symbol, no grouping commas.
  ///
  /// The display groups thousands, but `entry` holds what was typed, and a
  /// comma in there would come back through `parseToCents` as noise.
  static String _plainText(int cents) =>
      formatCents(cents, showSymbol: false).replaceAll(',', '');

  int get _decimalsTyped {
    final point = entry.indexOf('.');
    return point == -1 ? 0 : entry.length - point - 1;
  }

  /// Applies one operation, in integer minor units throughout.
  ///
  /// Addition and subtraction take two *amounts*. Multiplication and division
  /// do not: `1000 × 3` means an amount times a count, so the right-hand side
  /// is a plain number rather than money. Scaling by `cents / 100` expresses
  /// that without ever building a `double`, and rounds once at the end.
  static int? _apply(int left, AmountOperator operator, int right) =>
      switch (operator) {
        AmountOperator.add => left + right,
        AmountOperator.subtract => left - right,
        AmountOperator.multiply => _divideRounded(
          left * right,
          CurrencyFormat.lkr.minorUnitsPerMajor,
        ),
        AmountOperator.divide =>
          right == 0
              ? null
              : _divideRounded(
                  left * CurrencyFormat.lkr.minorUnitsPerMajor,
                  right,
                ),
      };

  /// Integer division rounding half away from zero.
  ///
  /// `~/` truncates, which would quietly lose a cent on every split bill and
  /// always in the same direction. Over a month of shared dinners that is a
  /// visible drift in the very totals this app exists to get right.
  static int _divideRounded(int numerator, int denominator) {
    final negative = (numerator < 0) != (denominator < 0);
    final n = numerator.abs();
    final d = denominator.abs();
    final magnitude = (2 * n + d) ~/ (2 * d);
    return negative ? -magnitude : magnitude;
  }
}
