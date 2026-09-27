import 'package:flutter/material.dart';

/// One line of text that shrinks to fit rather than overflowing. SRS §4.1.
///
/// For an amount beside a label: a figure must not wrap mid-number, and at
/// the largest font on a 320dp phone a seven-figure amount is wider than
/// the space left beside its label. Put it in a `Flexible` and it keeps its
/// size wherever it fits — every ordinary case — and scales down only where
/// it would otherwise be clipped or throw.
class ScaleDownText extends StatelessWidget {
  /// Creates the text.
  const ScaleDownText(
    this.data, {
    this.style,
    this.alignment = Alignment.centerRight,
    super.key,
  });

  /// What it says.
  final String data;

  /// How it looks, at full size.
  final TextStyle? style;

  /// Where it sits when it is smaller than its box.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: alignment,
    child: Text(data, style: style, maxLines: 1),
  );
}
