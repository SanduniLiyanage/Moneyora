import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
