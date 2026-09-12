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
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/core/theme/category_palette.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/period_selection.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_trend.dart';
import 'package:moneyora/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:moneyora/features/analytics/presentation/widgets/spending_trend_lines.dart';
import 'package:moneyora/injection.dart';

/// FR-RPT-005's trend lines over a scripted repository.
///
/// The use case beneath the chart is tested on its own; what is worth
/// asserting here is what the chart *does* with a trend — one line per
/// category, the tail folded, the legend carrying each total — and that it
/// asks the same question the donut and the bars ask, so the three cannot
/// drift apart on a filter change.

/// Answers `spendingTrend` from a script, recording what it was asked.
class _ScriptedRepository implements AnalyticsRepository {
  _ScriptedRepository({this.points = const [], this.failure, this.hold});

  final List<TrendPoint> points;
  final Failure? failure;
  final Completer<void>? hold;

  final List<AnalyticsQuery> asked = [];
  final List<TrendGranularity> askedGranularity = [];

  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) async {
    asked.add(query);
    askedGranularity.add(granularity);
    if (hold != null) await hold!.future;
    if (failure case final f?) return Left(f);
    return Right(points);
  }

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) =>
      throw UnimplementedError();
}

void main() {
  final anchor = DateTime(2026, 9, 9);

  TrendPoint point(
    DateTime bucket,
    int cents, {
    int categoryId = 1,
    String name = 'Food',
    String color = '#eb6834',
  }) => TrendPoint(
    bucket: bucket,
    categoryId: categoryId,
    name: name,
    color: color,
    amountCents: cents,
  );

  Widget boot(
    _ScriptedRepository repository, {
    PeriodSelection? selection,
    int transactionsEver = 1,
  }) => ProviderScope(
    overrides: [
      analyticsPeriodProvider.overrideWith(
        (ref) => selection ?? PeriodSelection.monthOf(anchor),
      ),
      getSpendingTrendProvider.overrideWith(
        (ref) async => GetSpendingTrend(repository),
      ),
      databaseSummaryProvider.overrideWith(
        (ref) async => DatabaseSummary(
          schemaVersion: 1,
          accounts: 1,
          categories: 18,
          transactions: transactionsEver,
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: SingleChildScrollView(child: SpendingTrendLines()),
      ),
    ),
  );

  LineChartData chartData(WidgetTester tester) =>
      tester.widget<LineChart>(find.byType(LineChart)).data;

  group('the lines', () {
    testWidgets('draws one line per category and names each in the legend', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            points: [
              point(DateTime(2026, 9, 3), 120000),
              point(DateTime(2026, 9, 14), 80000),
              point(
                DateTime(2026, 9, 3),
                500000,
                categoryId: 2,
                name: 'Transport',
                color: '#2a78d6',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);
      expect(chartData(tester).lineBarsData.length, 2);
      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
    });

    testWidgets('the legend carries each category\'s total for the period', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            points: [
              point(DateTime(2026, 9, 3), 120000),
              point(DateTime(2026, 9, 14), 80000),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rs2,000.00'), findsOneWidget);
    });

    testWidgets('every line spans every bucket, with zero where nothing was '
        'spent', (tester) async {
      await tester.pumpWidget(
        boot(_ScriptedRepository(points: [point(DateTime(2026, 9, 3), 1)])),
      );
      await tester.pumpAndSettle();

      final spots = chartData(tester).lineBarsData.single.spots;
      expect(spots.length, 30);
      expect(spots[2].y, 1);
      expect(spots.where((s) => s.y == 0).length, 29);
    });

    testWidgets('each line wears its category\'s colour', (tester) async {
      await tester.pumpWidget(
        boot(_ScriptedRepository(points: [point(DateTime(2026, 9, 3), 100)])),
      );
      await tester.pumpAndSettle();

      expect(
        chartData(tester).lineBarsData.single.color,
        categoryColorFor('#eb6834', Brightness.light),
      );
    });

    testWidgets('folds the tail past five categories into Other', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            points: [
              // Descending, so the last two are the ones folded.
              for (final (id, cents) in const [
                (1, 900000),
                (2, 800000),
                (3, 700000),
                (4, 600000),
                (5, 500000),
                (6, 12300),
                (7, 4500),
              ])
                point(
                  DateTime(2026, 9, 3),
                  cents,
                  categoryId: id,
                  name: 'Category $id',
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(chartData(tester).lineBarsData.length, 6);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Category 6'), findsNothing);
      expect(find.text('Category 7'), findsNothing);
      // 123.00 + 45.00, the two folded totals.
      expect(find.text('Rs168.00'), findsOneWidget);
    });

    testWidgets('Other is drawn in the outline colour, not a category\'s', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            points: [
              for (var id = 1; id <= 6; id++)
                point(
                  DateTime(2026, 9, 3),
                  (10 - id) * 1000,
                  categoryId: id,
                  name: 'Category $id',
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(LineChart));
      expect(
        chartData(tester).lineBarsData.last.color,
        Theme.of(context).colorScheme.outline.withValues(alpha: 0.45),
      );
    });
  });

  group('the axis', () {
    testWidgets('a month is labelled by day at both ends', (tester) async {
      await tester.pumpWidget(
        boot(_ScriptedRepository(points: [point(DateTime(2026, 9, 3), 1)])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sep 1'), findsOneWidget);
      expect(find.text('Sep 30'), findsOneWidget);
    });

    testWidgets('a year is labelled by month', (tester) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(points: [point(DateTime(2026, 3), 1)]),
          selection: PeriodSelection.monthOf(anchor)
              .withPeriod(AnalyticsPeriod.year),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jan'), findsOneWidget);
      expect(find.text('Dec'), findsOneWidget);
    });

    testWidgets('a span across years says which year each month is in', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(points: [point(DateTime(2026, 3), 1)]),
          selection: PeriodSelection.monthOf(anchor).withCustomRange(
            DateRange(from: DateTime(2025, 7), to: DateTime(2026, 6, 30)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jul 25'), findsOneWidget);
      expect(find.text('Jun 26'), findsOneWidget);
    });

    testWidgets('money on the axis is abbreviated', (tester) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(points: [point(DateTime(2026, 9, 3), 4000000)]),
        ),
      );
      await tester.pumpAndSettle();

      // Ceiling is 40,000 × 1.15 = 46,000; gridlines every quarter of that.
      expect(find.text('Rs11k'), findsOneWidget);
      expect(find.text('Rs23k'), findsOneWidget);
      expect(find.text('Rs34k'), findsOneWidget);
    });
  });

  group('the filters it shares with the donut and the bars', () {
    testWidgets('asks for the selected period over every account', (
      tester,
    ) async {
      final repository = _ScriptedRepository();

      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      expect(repository.asked.single.range, DateRange.month(2026, 9));
      expect(repository.asked.single.isAllAccounts, isTrue);
      expect(repository.askedGranularity.single, TrendGranularity.day);
    });

    testWidgets('a period change re-asks, and re-cuts the period', (
      tester,
    ) async {
      final repository = _ScriptedRepository();
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(SpendingTrendLines)))
          .read(analyticsPeriodProvider.notifier)
          .state = PeriodSelection.monthOf(anchor)
          .withPeriod(AnalyticsPeriod.year);
      await tester.pumpAndSettle();

      expect(repository.asked.last.range, DateRange.year(2026));
      expect(repository.askedGranularity.last, TrendGranularity.month);
    });

    testWidgets('an account change narrows the trend too (FR-RPT-003)', (
      tester,
    ) async {
      // The failure this guards is a chart under the filter row that looks
      // filtered and is not.
      final repository = _ScriptedRepository();
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(SpendingTrendLines)))
              .read(analyticsAccountFilterProvider.notifier)
              .state =
          2;
      await tester.pumpAndSettle();

      expect(repository.asked.last.accountId, 2);
    });

    testWidgets('names the period above the lines', (tester) async {
      await tester.pumpWidget(boot(_ScriptedRepository()));
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsOneWidget);
    });
  });

  group('the states around the data', () {
    testWidgets('shows a spinner while the trend is in flight', (tester) async {
      final held = Completer<void>();
      addTearDown(() {
        if (!held.isCompleted) held.complete();
      });

      await tester.pumpWidget(boot(_ScriptedRepository(hold: held)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('a quiet period says so, in its own words (E-22)', (
      tester,
    ) async {
      await tester.pumpWidget(boot(_ScriptedRepository()));
      await tester.pumpAndSettle();

      expect(find.text('No spending to chart in this period.'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('a first-time user is told what will appear here (E-22)', (
      tester,
    ) async {
      await tester.pumpWidget(boot(_ScriptedRepository(), transactionsEver: 0));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'How each category moves over time appears here once you have '
          'added an expense.',
        ),
        findsOneWidget,
      );
      expect(find.text('No spending to chart in this period.'), findsNothing);
    });

    testWidgets('a single day is refused as a trend, in a sentence', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(points: [point(DateTime(2026, 9, 9), 100)]),
          selection: PeriodSelection.monthOf(anchor)
              .withPeriod(AnalyticsPeriod.day),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'A single day has no trend. Pick a week or longer to see one.',
        ),
        findsOneWidget,
      );
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('a failing query shows its own message', (tester) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            failure: const CacheFailure('Could not read the database.'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not read the database.'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('an inverted custom interval shows the use case\'s refusal', (
      tester,
    ) async {
      final repository = _ScriptedRepository();
      await tester.pumpWidget(
        boot(
          repository,
          selection: PeriodSelection.monthOf(anchor).withCustomRange(
            DateRange(from: DateTime(2026, 9, 30), to: DateTime(2026, 9)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('The start of the period is after its end.'),
        findsOneWidget,
      );
      expect(repository.asked, isEmpty);
    });
  });
}
