@TestOn('vm')
library;

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
import 'package:moneyora/features/analytics/domain/entities/daily_total.dart';
import 'package:moneyora/features/analytics/domain/entities/period_selection.dart';
import 'package:moneyora/features/analytics/domain/entities/transfer_totals.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_period_summary.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_by_category.dart';
import 'package:moneyora/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:moneyora/features/analytics/presentation/widgets/spending_overview.dart';
import 'package:moneyora/injection.dart';

import 'large_text.dart';

/// The home screen's ring over scripted spending, income and categories.
class _Scripted implements AnalyticsRepository {
  _Scripted({this.spending = const [], this.income = 0});

  final List<CategoryTotal> spending;
  final int income;

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async => Right(spending);

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) async =>
      Right(income);

  @override
  Future<Either<Failure, TransferTotals>> transfersForPeriod(
    AnalyticsQuery query,
  ) async => const Right(TransferTotals.none);

  @override
  Future<Either<Failure, List<DailyTotal>>> dailySpendingTotals(
    AnalyticsQuery query,
  ) async => const Right([]);

  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) async => const Right([]);
}

class _Categories implements CategoryReader {
  const _Categories(this.options);

  final List<CategoryOption> options;

  @override
  Stream<Either<Failure, List<CategoryOption>>> watchAll() =>
      Stream.value(Right(options));
}

void main() {
  // Mid-September 2026, so the month is a whole one before "today".
  final today = DateTime(2026, 9, 16);

  const icons = [
    'basket',
    'car',
    'tshirt',
    'phone',
    'cutlery',
    'gift',
    'receipt',
    'cocktail',
  ];
  const names = [
    'Food',
    'Car',
    'Clothes',
    'Phone',
    'Eating out',
    'Gifts',
    'Bills',
    'Fun',
  ];

  CategoryOption category(int i) => CategoryOption(
    id: i + 1,
    name: names[i],
    icon: icons[i],
    colorHex: '#3f51b5',
    isExpense: true,
  );

  CategoryTotal spent(int i, int cents) => CategoryTotal(
    categoryId: i + 1,
    name: names[i],
    color: '#eb6834',
    amountCents: cents,
  );

  Widget boot({
    List<CategoryTotal> spending = const [],
    int income = 0,
    int transactionsEver = 5,
  }) {
    final repository = _Scripted(spending: spending, income: income);
    return ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => today),
        analyticsPeriodProvider.overrideWith(
          (ref) => PeriodSelection.monthOf(today),
        ),
        databaseSummaryProvider.overrideWith(
          (ref) async => DatabaseSummary(
            schemaVersion: 1,
            accounts: 1,
            categories: names.length,
            transactions: transactionsEver,
          ),
        ),
        categoryReaderProvider.overrideWith(
          (ref) async =>
              _Categories([for (var i = 0; i < names.length; i++) category(i)]),
        ),
        getSpendingByCategoryProvider.overrideWith(
          (ref) async => GetSpendingByCategory(repository),
        ),
        getPeriodSummaryProvider.overrideWith(
          (ref) async => GetPeriodSummary(repository),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: SpendingOverview()),
      ),
    );
  }

  testWidgets('each category spent on, by icon and share. FR-RPT-001', (
    tester,
  ) async {
    await tester.pumpWidget(
      boot(spending: [spent(0, 750000), spent(1, 250000)], income: 1500000),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PieChart), findsOneWidget);
    expect(find.byIcon(Icons.shopping_basket), findsOneWidget);
    expect(find.byIcon(Icons.directions_car), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    // Income over spending, in the middle.
    expect(find.text('Rs15,000.00'), findsOneWidget);
    expect(find.text('Rs10,000.00'), findsOneWidget);
    // Nothing for a category nothing was spent on.
    expect(find.byIcon(Icons.checkroom), findsNothing);
  });

  testWidgets('says the rest to a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(boot(spending: [spent(0, 750000)]));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        RegExp(r'Spending by category: Food 100%, Rs7,500\.00'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('past six, the smallest fold into one Other', (tester) async {
    await tester.pumpWidget(
      boot(spending: [for (var i = 0; i < 8; i++) spent(i, (8 - i) * 10000)]),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    // Bills and Fun, the two smallest, are inside Other.
    expect(find.byIcon(Icons.receipt_long), findsNothing);
    expect(find.byIcon(Icons.local_bar), findsNothing);
  });

  testWidgets('a quiet period says so, not "add your first"', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    expect(find.text('No spending in this period.'), findsOneWidget);
  });

  testWidgets('a new install says how to begin. E-22', (tester) async {
    await tester.pumpWidget(boot(transactionsEver: 0));
    await tester.pumpAndSettle();

    expect(find.text('Tap − to record your first expense.'), findsOneWidget);
  });

  testWidgets('the arrows step back, and not past this month', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);

    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byTooltip('Previous period'));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Next period'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
  });

  testWidgets('a swipe steps the period, as a page turns', (tester) async {
    await tester.pumpWidget(boot(spending: [spent(0, 750000)]));
    await tester.pumpAndSettle();

    // Towards the right: the month before.
    await tester.fling(find.byType(PieChart), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);

    // Towards the left: the month after.
    await tester.fling(find.byType(PieChart), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
  });

  testWidgets('holds at the largest font on a 320dp phone. SRS §4.1', (
    tester,
  ) async {
    useLargeTextOnSmallPhone(tester);
    await tester.pumpWidget(
      boot(
        spending: [for (var i = 0; i < 8; i++) spent(i, 123456789 - i * 1000)],
        income: 987654321,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PieChart), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
  });
}
