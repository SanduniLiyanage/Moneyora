import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Whether a list row's amount fits beside its title at the user's font
/// size: the title keeps at least [floor], and at least the width of the
/// longest of [words], so no word of it breaks in the middle. SRS §4.1.
///
/// At the largest font on a 320dp phone an amount on the right of a row
/// left its title about 80dp, and one word broke across lines: "Deb/t",
/// "Platinu/m", "Availabl/e". Where it would, the row puts the amount
/// under the title instead, and the title has the row. [chrome] is the
/// rest of the row: its padding, its leading widget and the gaps either
/// side of the title, Material 3's 16 + 40 + 16 + 16 + 24 for a row with a
/// 40dp avatar. [trailing] is anything else on the right. [words] are the
/// texts beside the amount, each with its style.
bool amountFitsBeside(
  BuildContext context, {
  required double rowWidth,
  required String amount,
  TextStyle? style,
  List<(String, TextStyle?)> words = const [],
  double chrome = 112,
  double trailing = 0,
  double floor = 96,
  double maxWidthFactor = 0.45,
}) {
  double widthOf(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  // No wider than ScaleDownText lets an amount be.
  final amountWidth = math.min(
    widthOf(amount, style),
    MediaQuery.sizeOf(context).width * maxWidthFactor,
  );
  var needed = floor;
  for (final (text, wordStyle) in words) {
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      needed = math.max(needed, widthOf(word, wordStyle));
    }
  }
  return rowWidth - chrome - amountWidth - trailing >= needed;
}
