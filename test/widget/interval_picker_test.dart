@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/presentation/widgets/interval_picker.dart';

import 'large_text.dart';

/// FR-RPT-002's interval, on the calendar that swipes between months.
void main() {
  final first = DateTime(2000);
  final last = DateTime(2026, 10, 6);

  /// A button that opens the picker and keeps what it answered.
  Future<List<DateRange?>> open(
    WidgetTester tester, {
    DateRange? initial,
  }) async {
    final answers = <DateRange?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answers.add(
                await showIntervalPicker(
                  context,
                  initial: initial,
                  first: first,
                  last: last,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return answers;
  }

  /// [day] in the month on show.
  Future<void> tapDay(WidgetTester tester, int day) async {
    await tester.tap(
      find.descendant(of: find.byType(PageView), matching: find.text('$day')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the month of today, the last day it allows', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Tap the first day'), findsOneWidget);
  });

  testWidgets('opens on the month an interval already ends in', (tester) async {
    await open(
      tester,
      initial: DateRange(from: DateTime(2026, 3, 4), to: DateTime(2026, 5, 6)),
    );

    expect(find.text('May 2026'), findsOneWidget);
    expect(find.text('Mar 4, 2026 – May 6, 2026'), findsOneWidget);
  });

  testWidgets('a swipe turns the month', (tester) async {
    await open(tester);

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('two taps are the first and last day', (tester) async {
    final answers = await open(tester);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    await tapDay(tester, 3);
    expect(find.text('Sep 3, 2026 – tap the last day'), findsOneWidget);
    await tapDay(tester, 12);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(answers, [
      DateRange(from: DateTime(2026, 9, 3), to: DateTime(2026, 9, 12)),
    ]);
  });

  testWidgets('the last day can be in another month', (tester) async {
    final answers = await open(tester);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    await tapDay(tester, 25);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tapDay(tester, 5);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(answers, [
      DateRange(from: DateTime(2026, 9, 25), to: DateTime(2026, 10, 5)),
    ]);
  });

  testWidgets('a second tap before the first ends it the other way', (
    tester,
  ) async {
    final answers = await open(tester);

    await tapDay(tester, 5);
    await tapDay(tester, 2);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(answers, [
      DateRange(from: DateTime(2026, 10, 2), to: DateTime(2026, 10, 5)),
    ]);
  });

  testWidgets('one tap and OK is that one day', (tester) async {
    final answers = await open(tester);

    await tapDay(tester, 4);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(answers, [
      DateRange(from: DateTime(2026, 10, 4), to: DateTime(2026, 10, 4)),
    ]);
  });

  testWidgets('OK waits for a day, and no day after today is offered', (
    tester,
  ) async {
    await open(tester);

    final ok = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'OK'),
    );
    expect(ok.onPressed, isNull);

    await tapDay(tester, 20);
    expect(find.text('Tap the first day'), findsOneWidget);
  });

  testWidgets('Cancel answers nothing', (tester) async {
    final answers = await open(tester);

    await tapDay(tester, 4);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answers, [null]);
  });

  testWidgets('holds at the largest font on a 320dp phone. SRS §4.1', (
    tester,
  ) async {
    useLargeTextOnSmallPhone(tester);
    final answers = await open(tester);

    await tapDay(tester, 1);
    await tester.ensureVisible(find.text('OK'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(answers, hasLength(1));
  });
}
