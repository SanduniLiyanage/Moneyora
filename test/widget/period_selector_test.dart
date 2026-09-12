@TestOn('vm')
library;

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/database/database_summary.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/period_selection.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_by_category.dart';
import 'package:moneyora/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:moneyora/features/analytics/presentation/widgets/period_selector.dart';
import 'package:moneyora/features/analytics/presentation/widgets/spending_donut_chart.dart';
import 'package:moneyora/injection.dart';

/// The period picker through the chart it filters. FR-RPT-002.
///
/// The selector is tested here rather than in isolation because the thing
/// worth asserting is not which chip looks selected — it is *which range the
/// query was asked for* after a tap, and that only exists once the chart
/// beneath it watches the same providers the real screen does.

/// Records every range it is asked for, in order.
class _RecordingRepository implements AnalyticsRepository {
  final List<DateRange> asked = [];

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async {
    asked.add(query.range);
    return const Right([
      CategoryTotal(
        categoryId: 1,
        name: 'Food',
        color: '#eb6834',
        amountCents: 342000,
      ),
    ]);
  }

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) =>
      throw UnimplementedError();
  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) => throw UnimplementedError();
}

class _FakeCategoryReader implements CategoryReader {
  @override
  Stream<Either<Failure, List<CategoryOption>>> watchAll() =>
      Stream.value(const Right([]));
}

void main() {
  // A Wednesday in a month with a full history behind it, so every period
  // below is a stated date rather than whatever day the suite happens to run.
  final anchor = DateTime(2026, 9, 9);

  late _RecordingRepository repository;

  setUp(() => repository = _RecordingRepository());

  Widget boot({
    Either<Failure, List<CategoryTotal>>? spendingResult,
    int transactionsEver = 5,
    Completer<void>? hold,
  }) => ProviderScope(
    overrides: [
      analyticsPeriodProvider.overrideWith(
        (ref) => PeriodSelection.monthOf(anchor),
      ),
      databaseSummaryProvider.overrideWith(
        (ref) async => DatabaseSummary(
          schemaVersion: 1,
          accounts: 1,
          categories: 0,
          transactions: transactionsEver,
        ),
      ),
      categoryReaderProvider.overrideWith((ref) async => _FakeCategoryReader()),
      getSpendingByCategoryProvider.overrideWith((ref) async {
        if (hold != null) await hold.future;
        return GetSpendingByCategory(
          spendingResult == null
              ? repository
              : _ScriptedRepository(spendingResult),
        );
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: SpendingDonutChart()),
    ),
  );

  /// The selection the running widget tree holds, read the way the widget
  /// reads it rather than through a container of its own.
  PeriodSelection selectionOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SpendingDonutChart)))
          .read(analyticsPeriodProvider);

  void setSelection(WidgetTester tester, PeriodSelection selection) {
    ProviderScope.containerOf(tester.element(find.byType(SpendingDonutChart)))
            .read(analyticsPeriodProvider.notifier)
            .state =
        selection;
  }

  group('the period the chart opens on', () {
    testWidgets('is the current calendar month, as FR-RPT-001 shipped it', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsOneWidget);
      expect(repository.asked.single, DateRange.month(2026, 9));
    });

    testWidgets('offers every filter FR-RPT-002 names', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      for (final label in ['Day', 'Week', 'Month', 'Year', 'All', 'Custom']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      // "Choose Date" is the button, not a seventh chip.
      expect(find.byTooltip('Choose date'), findsOneWidget);
    });
  });

  group('switching period', () {
    Future<void> tapChip(WidgetTester tester, String label) async {
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pumpAndSettle();
    }

    testWidgets('Day queries that one day', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      await tapChip(tester, 'Day');

      expect(repository.asked.last, DateRange.day(anchor));
      expect(find.text('September 9, 2026'), findsOneWidget);
    });

    testWidgets('Week queries Monday to Sunday around the anchor', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      await tapChip(tester, 'Week');

      expect(repository.asked.last, DateRange.week(anchor));
      expect(
        repository.asked.last,
        DateRange(from: DateTime(2026, 9, 7), to: DateTime(2026, 9, 13)),
      );
    });

    testWidgets('Year queries the whole calendar year', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      await tapChip(tester, 'Year');

      expect(repository.asked.last, DateRange.year(2026));
      expect(find.text('2026'), findsOneWidget);
    });

    testWidgets('All queries every date a row can hold', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      await tapChip(tester, 'All');

      expect(repository.asked.last, DateRange.allTime());
      expect(find.text('All time'), findsOneWidget);
    });

    testWidgets('Month comes back to the month, not to today', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      await tapChip(tester, 'Day');
      await tapChip(tester, 'Month');

      expect(repository.asked.last, DateRange.month(2026, 9));
      expect(selectionOf(tester).period, AnalyticsPeriod.month);
    });

    testWidgets('re-queries once per change, not once per rebuild', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      await tapChip(tester, 'Day');
      await tester.pump();
      await tester.pump();

      expect(repository.asked, [
        DateRange.month(2026, 9),
        DateRange.day(anchor),
      ]);
    });
  });

  group('Choose Date', () {
    testWidgets('re-anchors the selected period without changing it', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Choose date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // The picker opens on the anchor's month; step back one and take the 1st.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(selectionOf(tester).period, AnalyticsPeriod.month);
      expect(repository.asked.last, DateRange.month(2026, 8));
      expect(find.text('August 2026'), findsOneWidget);
    });

    testWidgets('cancelling leaves the period exactly as it was', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      final before = selectionOf(tester);

      await tester.tap(find.byTooltip('Choose date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(selectionOf(tester), before);
      expect(repository.asked, [DateRange.month(2026, 9)]);
    });

    testWidgets('is disabled for All and Custom, which no date anchors', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.event_outlined),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('Custom Interval', () {
    testWidgets('the chip opens the range picker rather than selecting an '
        'interval that does not exist yet', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Custom'));
      await tester.pumpAndSettle();

      expect(find.byType(DateRangePickerDialog), findsOneWidget);
    });

    testWidgets('cancelling the range picker does not switch period', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(selectionOf(tester).period, AnalyticsPeriod.month);
      expect(repository.asked, [DateRange.month(2026, 9)]);
    });

    testWidgets('a picked interval is the range the query is asked for', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      final interval = DateRange(
        from: DateTime(2026, 3, 4),
        to: DateTime(2026, 5, 6),
      );
      setSelection(
        tester,
        PeriodSelection.monthOf(anchor).withCustomRange(interval),
      );
      await tester.pumpAndSettle();

      expect(repository.asked.last, interval);
      expect(find.text('Mar 4 – May 6, 2026'), findsOneWidget);
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('an inverted interval is refused in the use case\'s own '
        'words, not answered with an empty chart', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      setSelection(
        tester,
        PeriodSelection.monthOf(anchor).withCustomRange(
          DateRange(from: DateTime(2026, 5, 6), to: DateTime(2026, 3, 4)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('The start of the period is after its end.'),
        findsOneWidget,
      );
      expect(find.byType(PieChart), findsNothing);
      expect(find.text('No spending in this period.'), findsNothing);
    });
  });

  group('the chart\'s other states survive a period change', () {
    testWidgets('a period whose query has not resolved shows the spinner', (
      tester,
    ) async {
      final held = Completer<void>();
      addTearDown(() {
        if (!held.isCompleted) held.complete();
      });

      await tester.pumpWidget(boot(hold: held));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The picker is still usable while the query beneath it is in flight.
      expect(find.widgetWithText(ChoiceChip, 'Day'), findsOneWidget);
    });

    testWidgets('an empty period keeps E-22\'s two sentences apart', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(spendingResult: const Right([]), transactionsEver: 400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Day'));
      await tester.pumpAndSettle();

      expect(find.text('No spending in this period.'), findsOneWidget);
      expect(
        find.textContaining('once you have added an expense'),
        findsNothing,
      );
    });

    testWidgets('a failing query still shows the failure after a switch', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          spendingResult: const Left(
            CacheFailure(
              'Could not read the '
              'database.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Year'));
      await tester.pumpAndSettle();

      expect(find.text('Could not read the database.'), findsOneWidget);
      expect(find.byType(PieChart), findsNothing);
      expect(find.text('2026'), findsOneWidget);
    });
  });

  group('the caption above the chart', () {
    testWidgets('names the interval rather than a month it is not', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      setSelection(
        tester,
        PeriodSelection.monthOf(anchor).withCustomRange(
          DateRange(from: DateTime(2025, 12, 30), to: DateTime(2026, 1, 2)),
        ),
      );
      await tester.pumpAndSettle();

      // Both years stated, because the interval crosses one.
      expect(find.text('Dec 30, 2025 – Jan 2, 2026'), findsOneWidget);
    });

    test('a week inside one year states that year once', () {
      final label = periodLabel(
        PeriodSelection(period: AnalyticsPeriod.week, anchor: anchor),
      );

      expect(label, 'Sep 7 – Sep 13, 2026');
    });
  });
}

/// A repository with one scripted answer, for the empty and failing cases.
class _ScriptedRepository implements AnalyticsRepository {
  _ScriptedRepository(this.result);

  final Either<Failure, List<CategoryTotal>> result;

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async => result;

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) =>
      throw UnimplementedError();
  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) => throw UnimplementedError();
}
