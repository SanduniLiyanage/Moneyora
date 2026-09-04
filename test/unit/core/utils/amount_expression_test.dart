import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/utils/amount_expression.dart';

/// The keypad's rules, tested without a keypad.
///
/// Every one of these is a keystroke sequence a person will actually perform,
/// written as the sequence rather than as a call to an internal method, so the
/// test says what the user did and not how the class is built.
void main() {
  AmountExpression keyIn(String keys) {
    var expression = AmountExpression.empty();
    for (final key in keys.split('')) {
      expression = switch (key) {
        '+' => expression.operation(AmountOperator.add),
        '-' => expression.operation(AmountOperator.subtract),
        '*' => expression.operation(AmountOperator.multiply),
        '/' => expression.operation(AmountOperator.divide),
        '=' => expression.evaluated(),
        '<' => expression.backspace(),
        'C' => expression.cleared(),
        '.' => expression.decimalPoint(),
        _ => expression.digit(key),
      };
    }
    return expression;
  }

  int? cents(String keys) => keyIn(keys).valueCents;

  group('typing an amount', () {
    test('digits become minor units', () {
      expect(cents('1250'), 125000);
      expect(cents('7'), 700);
    });

    test('a decimal point gives the cents', () {
      expect(cents('12.50'), 1250);
      expect(cents('0.05'), 5);
    });

    test('nothing typed evaluates to nothing, not to zero', () {
      // A zero here would be a transaction that looks saved and is wrong.
      expect(cents(''), isNull);
      expect(AmountExpression.empty().isEmpty, isTrue);
    });

    test('a leading zero is replaced rather than extended', () {
      expect(keyIn('05').display, '5');
    });

    test('a second decimal point is ignored', () {
      expect(keyIn('1.5.2').display, '1.52');
    });

    test('a third decimal digit is refused, not silently rounded later', () {
      // LKR has two decimal places. Accepting a third and rounding it away at
      // save time is a small lie the user only discovers afterwards.
      expect(keyIn('1.239').display, '1.23');
    });

    test('a bare decimal point starts at zero', () {
      expect(keyIn('.5').display, '0.5');
      expect(cents('.5'), 50);
    });
  });

  group('arithmetic', () {
    test('adds two amounts — the receipt case', () {
      // Rs 1,250 of groceries and a Rs 340 bus fare.
      expect(cents('1250+340'), 159000);
    });

    test('subtracts', () {
      expect(cents('1000-250'), 75000);
    });

    test('multiplies by a count, not by an amount', () {
      // Four coffees at 350 is 1,400 — not 350 × 35,000 cents.
      expect(cents('350*4'), 140000);
    });

    test('divides by a count — a bill split', () {
      expect(cents('1200/3'), 40000);
    });

    test('handles a fractional multiplier', () {
      expect(cents('100*1.5'), 15000);
    });

    test('evaluates left to right, with no operator precedence', () {
      // 100 + 20 = 120, then × 3 = 360. Under precedence it would be 160.
      // The keypad shows the running total after each operator, so precedence
      // would make the number on screen a lie until the user pressed equals.
      expect(cents('100+20*3'), 36000);
    });

    test('a division by zero resolves to nothing rather than throwing', () {
      // Not an error worth a message — Save simply stays disabled.
      expect(cents('100/0'), isNull);
    });
  });

  group('rounding', () {
    test('a three-way split rounds rather than truncating', () {
      // 1000 / 3 = 333.333…, which must round to 333.33 and not fall to
      // 333.32. Truncation loses a cent every time and always downward, so a
      // month of shared dinners drifts visibly.
      expect(cents('1000/3'), 33333);
    });

    test('rounds half away from zero', () {
      // 0.05 / 2 = 0.025 → 3 cents, not 2.
      expect(cents('0.05/2'), 3);
    });

    test('a negative intermediate rounds symmetrically', () {
      expect(cents('0-0.05/2'), -3);
    });
  });

  group('correcting a mistake', () {
    test('backspace removes one digit', () {
      expect(keyIn('1234<').display, '123');
    });

    test('backspace after an operator removes the operator', () {
      expect(keyIn('100+<').display, '100.00');
      expect(keyIn('100+<').pendingOperator, isNull);
    });

    test('a second operator replaces the first', () {
      // Hitting + when you meant − should not add a phantom zero term.
      expect(cents('100+-40'), 6000);
    });

    test('clear empties everything', () {
      expect(keyIn('100+40C').isEmpty, isTrue);
    });

    test('backspace on an empty keypad is harmless', () {
      expect(keyIn('<<<').isEmpty, isTrue);
    });
  });

  group('equals', () {
    test('collapses the expression to its result', () {
      final result = keyIn('1250+340=');

      expect(result.pendingOperator, isNull);
      expect(result.valueCents, 159000);
    });

    test('the result can be used as the start of the next sum', () {
      expect(cents('1250+340=+10'), 160000);
    });

    test('equals on an empty keypad does nothing', () {
      expect(keyIn('=').isEmpty, isTrue);
    });
  });

  group('display', () {
    test('shows a placeholder zero when empty', () {
      expect(AmountExpression.empty().display, '0');
    });

    test('shows the running total and the pending operator', () {
      // Grouped, because the running total is money and formatCents is the
      // only thing in the app allowed to render it.
      expect(keyIn('1250+').display, '1,250.00 +');
      expect(keyIn('1250+34').display, '1,250.00 + 34');
    });
  });
}
