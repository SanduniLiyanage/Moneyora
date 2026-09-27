import 'package:flutter/material.dart';

/// One line of text that shrinks to fit rather than overflowing. SRS §4.1.
///
/// For an amount beside a label: a figure must not wrap mid-number, and at
/// the largest font on a 320dp phone a seven-figure amount is wider than
/// the space left beside its label. It takes at most [maxWidthFactor] of
/// the screen's width and keeps its size wherever it fits — every ordinary
/// case — scaling down only where it would otherwise be clipped or throw.
///
/// Not inside a `Flexible`: that splits the row evenly with the label, so
/// a short amount sits mid-card and a long name breaks mid-word.
class ScaleDownText extends StatelessWidget {
  /// Creates the text.
  const ScaleDownText(
    this.data, {
    this.style,
    this.alignment = Alignment.centerRight,
    this.maxWidthFactor = 0.45,
    super.key,
  });

  /// What it says.
  final String data;

  /// How it looks, at full size.
  final TextStyle? style;

  /// Where it sits when it is smaller than its box.
  final AlignmentGeometry alignment;

  /// The most of the screen's width it may take.
  final double maxWidthFactor;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * maxWidthFactor,
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(data, style: style, maxLines: 1),
    ),
  );
}
