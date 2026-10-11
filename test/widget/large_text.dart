import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether [text] is drawn short of itself: ellipsised, past its line
/// limit, or wrapped into a box too small to show every line. None of
/// these throws the way an overflowing Row does, so a test has to ask.
bool isCut(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  // ignore: invalid_use_of_visible_for_testing_member
  final drawn = paragraph.textSize;
  return paragraph.didExceedMaxLines ||
      drawn.width > paragraph.size.width + 0.5 ||
      drawn.height > paragraph.size.height + 0.5;
}

/// WCAG 2.1's contrast ratio between two opaque colours, 1 to 21.
double contrastBetween(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

/// Android's largest font on the smallest supported phone: 2x text on
/// 320x640dp. SRS §4.1. A layout that overflows throws in the test.
void useLargeTextOnSmallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(960, 1920)
    ..devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// The smallest supported phone at the ordinary font: 320x640dp.
///
/// For a label's width rather than a layout's: the test font draws every
/// letter a full em wide, about twice Roboto's average, so a label that
/// fits here fits a real phone at its largest font, and one that does not
/// was cut there.
void useSmallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(960, 1920)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Drags the first list on screen to its end, so every row in it is laid
/// out at least once.
Future<void> scrollToEnd(WidgetTester tester) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 60; i++) {
    final position = tester.state<ScrollableState>(list).position;
    if (position.pixels >= position.maxScrollExtent) return;
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
}
