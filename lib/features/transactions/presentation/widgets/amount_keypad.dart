import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/amount_expression.dart';

/// The custom numeric keypad on the entry screen. FR-EXP-002.
///
/// A system keyboard would work and would be wrong. Entering money is a
/// four-tap job — amount, category, save — and a keyboard designed for prose
/// puts a comma, a colon and an emoji key between the user and a digit.
///
/// The widget owns no arithmetic. Every keypress hands an [AmountExpression]
/// back through [onChanged], and the rules for what a key *means* live in
/// `core/utils/amount_expression.dart`, where they are tested without a
/// device.
class AmountKeypad extends StatelessWidget {
  /// Creates the keypad.
  const AmountKeypad({
    required this.expression,
    required this.onChanged,
    super.key,
  });

  /// What has been keyed so far.
  final AmountExpression expression;

  /// Called with the expression that results from a keypress.
  final ValueChanged<AmountExpression> onChanged;

  @override
  Widget build(BuildContext context) {
    // Four rows of four: digits on the left three columns, operators on the
    // right, in the order a calculator puts them so muscle memory transfers.
    const rows = <List<String>>[
      ['7', '8', '9', '÷'],
      ['4', '5', '6', '×'],
      ['1', '2', '3', '−'],
      ['.', '0', '⌫', '+'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Row(
            children: [
              for (final key in row)
                Expanded(
                  child: _Key(label: key, onTap: () => _press(key)),
                ),
            ],
          ),
      ],
    );
  }

  void _press(String key) {
    final next = switch (key) {
      '÷' => expression.operation(AmountOperator.divide),
      '×' => expression.operation(AmountOperator.multiply),
      '−' => expression.operation(AmountOperator.subtract),
      '+' => expression.operation(AmountOperator.add),
      '.' => expression.decimalPoint(),
      '⌫' => expression.backspace(),
      _ => expression.digit(key),
    };
    onChanged(next);
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  bool get _isOperator => '÷×−+'.contains(label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Semantics(
      button: true,
      label: switch (label) {
        '⌫' => 'Backspace',
        '÷' => 'Divide',
        '×' => 'Multiply',
        '−' => 'Subtract',
        '+' => 'Add',
        '.' => 'Decimal point',
        _ => label,
      },
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          // 64 is comfortably past the 48dp minimum touch target, because this
          // is the control the app is used through and a mis-tap here costs a
          // wrong amount rather than a wasted second.
          height: 64,
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: _isOperator ? FontWeight.w600 : FontWeight.w400,
                color: _isOperator ? colors.brand : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
