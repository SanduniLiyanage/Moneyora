import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/amount_expression.dart';

/// The custom numeric keypad on the entry screen. FR-EXP-002.
///
/// A system keyboard would work and would be wrong. Entering money is a
/// three-tap job — amount, category, done — and a keyboard designed for prose
/// puts a comma, a colon and an emoji key between the user and a digit.
///
/// Four rows of four outlined keys: the digits from 1 at the top left, the
/// four operators down the right, and `=` beside 0. Backspace is on the
/// amount itself, where the digit it removes is.
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
    this.keyHeight = 64,
    this.accent,
    super.key,
  });

  /// What has been keyed so far.
  final AmountExpression expression;

  /// Called with the expression that results from a keypress.
  final ValueChanged<AmountExpression> onChanged;

  /// How tall each key is. 64 is comfortably past the 48dp minimum touch
  /// target, because this is the control the app is used through and a
  /// mis-tap here costs a wrong amount rather than a wasted second; a short
  /// phone trades that margin for room to see what the amount is for.
  final double keyHeight;

  /// The keys' outline: the colour of what is being entered, an expense's
  /// or an income's. The brand colour when not given.
  final Color? accent;

  static const List<List<String>> _rows = [
    ['1', '2', '3', '+'],
    ['4', '5', '6', '−'],
    ['7', '8', '9', '×'],
    ['.', '0', '=', '÷'],
  ];

  @override
  Widget build(BuildContext context) {
    final outline = accent ?? Theme.of(context).extension<AppColors>()!.brand;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Row(
            children: [
              for (final key in row)
                Expanded(
                  child: _Key(
                    label: key,
                    height: keyHeight,
                    outline: outline,
                    onTap: () => _press(key),
                  ),
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
      '=' => expression.evaluated(),
      '.' => expression.decimalPoint(),
      _ => expression.digit(key),
    };
    onChanged(next);
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.height,
    required this.outline,
    required this.onTap,
  });

  final String label;
  final double height;
  final Color outline;
  final VoidCallback onTap;

  bool get _isOperator => '÷×−+='.contains(label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Semantics(
      button: true,
      label: switch (label) {
        '÷' => 'Divide',
        '×' => 'Multiply',
        '−' => 'Subtract',
        '+' => 'Add',
        '=' => 'Equals',
        '.' => 'Decimal point',
        _ => label,
      },
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: outline.withValues(alpha: 0.45)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: _isOperator
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: _isOperator
                          ? colors.brand
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
