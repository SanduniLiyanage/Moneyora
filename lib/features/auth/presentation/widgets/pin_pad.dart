import 'package:flutter/material.dart';

import '../../domain/entities/passcode_format.dart';

/// A numeric keypad and the dots above it. FR-SET-005.
///
/// Controlled, not stateful: the screen owns the digits typed so far and is
/// told about every change, which is what lets it clear the row after a
/// wrong PIN or hand the same pad three different prompts in a row. A PIN is
/// four to six digits, so the length alone cannot say when the user is
/// done — the tick key does, and is enabled only once there are enough.
///
/// Its own keys rather than the system keyboard: a keyboard slides up over
/// half the lock screen and offers letters a PIN cannot contain, and a pad
/// drawn by the app looks the same on every device.
class PinPad extends StatelessWidget {
  /// Creates a pad showing [entered] and reporting each change.
  const PinPad({
    required this.entered,
    required this.onChanged,
    required this.onSubmit,
    this.enabled = true,
    super.key,
  });

  /// The digits typed so far.
  final String entered;

  /// Called with the new value after a digit or a backspace.
  final ValueChanged<String> onChanged;

  /// Called when the tick is pressed with an acceptable number of digits.
  final VoidCallback onSubmit;

  /// Whether the keys respond. Off while a PIN is being checked and during
  /// a lockout.
  final bool enabled;

  bool get _canSubmit => enabled && PasscodeFormat.validate(entered) == null;

  void _press(String digit) {
    if (!enabled || entered.length >= PasscodeFormat.maxLength) return;
    onChanged(entered + digit);
  }

  void _backspace() {
    if (!enabled || entered.isEmpty) return;
    onChanged(entered.substring(0, entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label:
              'PIN, ${entered.length} of up to ${PasscodeFormat.maxLength} '
              'digits',
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < PasscodeFormat.maxLength; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _Dot(filled: i < entered.length),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final digit in row)
                _Key(
                  label: digit,
                  onPressed: enabled ? () => _press(digit) : null,
                ),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Key(
              icon: Icons.backspace_outlined,
              tooltip: 'Delete',
              onPressed: enabled && entered.isNotEmpty ? _backspace : null,
            ),
            _Key(label: '0', onPressed: enabled ? () => _press('0') : null),
            _Key(
              icon: Icons.check,
              tooltip: 'Continue',
              onPressed: _canSubmit ? onSubmit : null,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? colour : Colors.transparent,
        border: Border.all(color: colour, width: 1.5),
      ),
    );
  }
}

/// One key: a digit, or an icon with a tooltip that doubles as its label.
class _Key extends StatelessWidget {
  const _Key({
    required this.onPressed,
    this.label,
    this.icon,
    this.tooltip,
    this.color,
  }) : assert(label != null || icon != null, 'a key needs a face');

  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox.square(
        dimension: 72,
        child: icon != null
            ? IconButton(
                onPressed: onPressed,
                tooltip: tooltip,
                icon: Icon(icon, color: onPressed == null ? null : color),
                iconSize: 28,
              )
            : TextButton(
                onPressed: onPressed,
                style: TextButton.styleFrom(
                  shape: const CircleBorder(),
                  foregroundColor: theme.colorScheme.onSurface,
                  textStyle: theme.textTheme.headlineSmall,
                ),
                child: Text(label!),
              ),
      ),
    );
  }
}
