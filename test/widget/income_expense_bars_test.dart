@TestOn('vm')
library;

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/core/theme/app_colors.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/period_selection.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_income_for_period.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_by_category.dart';
import 'package:moneyora/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:moneyora/features/analytics/presentation/widgets/income_expense_bars.dart';
import 'package:moneyora/injection.dart';

/// FR-RPT-004's bars over a scripted repository.
///
/// The chart's two numbers come from two different aggregates, so what is
/// worth asserting is that both are asked the *same* question — the same
/// period and the same account — and that the net figure it highlights is the
/// difference between the two answers.

/// Answers both aggregates from a script, recording what each was asked.
class _ScriptedRepository implements AnalyticsRepository {
  _ScriptedRepository({
    this.incomeCents = 0,
    this.totals = const [],
    this.incomeFailure,
    this.spendingFailure,
    this.hold,
  });

  final int incomeCents;
  final List<CategoryTotal> totals;
  final Failure? incomeFailure;
  final Failure? spendingFailure;
  final Completer<void>? hold;

  final List<AnalyticsQuery> askedIncome = [];
  final List<AnalyticsQuery> askedSpending = [];

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) async {
    askedIncome.add(query);
    if (hold != null) await hold!.future;
    if (incomeFailure case final failure?) return Left(failure);
    return Right(incomeCents);
  }

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async {
    askedSpending.add(query);
    if (spendingFailure case final failure?) return Left(failure);
    return Right(totals);
  }

  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) => throw UnimplementedError();
}

class _FakeAccountReader implements AccountReader {
  @override
  Stream<Either<Failure, List<AccountOption>>> watchAll() => Stream.value(
    const Right([
      AccountOption(id: 1, name: 'Cash', balanceCents: 0),
      AccountOption(id: 2, name: 'Payment card', balanceCents: 0),
    ]),
  );
}

void main() {
  final anchor = DateTime(2026, 9, 9);

  CategoryTotal total(String name, int cents) => CategoryTotal(
    categoryId: 1,
    name: name,
    color: '#eb6834',
    amountCents: cents,
  );

  Widget boot(_ScriptedRepository repository) => ProviderScope(
    overrides: [
      analyticsPeriodProvider.overrideWith(
        (ref) => PeriodSelection.monthOf(anchor),
      ),
      accountReaderProvider.overrideWith((ref) async => _FakeAccountReader()),
      getIncomeForPeriodProvider.overrideWith(
        (ref) async => GetIncomeForPeriod(repository),
      ),
      getSpendingByCategoryProvider.overrideWith(
        (ref) async => GetSpendingByCategory(repository),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: IncomeExpenseBars()),
    ),
  );

  group('the comparison', () {
    testWidgets('draws a bar for each side and names them', (tester) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            incomeCents: 8000000,
            totals: [total('Food', 342000), total('Transport', 114000)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Expenses'), findsOneWidget);
    });

    testWidgets('the expense side is the spending rows added up, not a third '
        'query', (tester) async {
      final repository = _ScriptedRepository(
        incomeCents: 8000000,
        totals: [total('Food', 342000), total('Transport', 114000)],
      );

      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      // 80,000.00 income less 4,560.00 spent.
      expect(find.text('Rs75,440.00'), findsOneWidget);
      expect(repository.askedSpending.length, 1);
    });

    testWidgets('asks both aggregates the same question', (tester) async {
      final repository = _ScriptedRepository(incomeCents: 100, totals: []);

      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      expect(repository.askedIncome.single, repository.askedSpending.single);
      expect(repository.askedIncome.single.range, DateRange.month(2026, 9));
      expect(repository.askedIncome.single.isAllAccounts, isTrue);
    });
  });

  group('net savings, highlighted. FR-RPT-004', () {
    testWidgets('states the surplus in words and in money', (tester) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            incomeCents: 8000000,
            totals: [total('Food', 3000000)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Net savings'), findsOneWidget);
      expect(find.text('Rs50,000.00'), findsOneWidget);
      expect(find.text('Overspent'), findsNothing);
    });

    testWidgets('says overspent rather than showing a negative saving', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            incomeCents: 3000000,
            totals: [total('Food', 8000000)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overspent'), findsOneWidget);
      expect(find.text('Net savings'), findsNothing);
      // The amount is shown positive beside the word, not as "-Rs50,000.00".
      expect(find.text('Rs50,000.00'), findsOneWidget);
    });

    testWidgets('breaking even is savings of nothing, not overspending', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            incomeCents: 500000,
            totals: [total('Food', 500000)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Net savings'), findsOneWidget);
      expect(find.text('Rs0.00'), findsOneWidget);
    });

    testWidgets('colours a surplus with the income colour', (tester) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            incomeCents: 8000000,
            totals: [total('Food', 3000000)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final amount = tester.widget<Text>(find.text('Rs50,000.00'));
      expect(amount.style?.color, AppColors.light.income);
    });

    testWidgets('colours a deficit with the expense colour', (tester) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            incomeCents: 3000000,
            totals: [total('Food', 8000000)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final amount = tester.widget<Text>(find.text('Rs50,000.00'));
      expect(amount.style?.color, AppColors.light.expense);
    });
  });

  group('the filters it shares with the donut', () {
    testWidgets('a period change moves both aggregates', (tester) async {
      final repository = _ScriptedRepository(incomeCents: 100, totals: []);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(IncomeExpenseBars)))
          .read(analyticsPeriodProvider.notifier)
          .state = PeriodSelection.monthOf(anchor)
          .withPeriod(AnalyticsPeriod.year);
      await tester.pumpAndSettle();

      expect(repository.askedIncome.last.range, DateRange.year(2026));
      expect(repository.askedSpending.last.range, DateRange.year(2026));
    });

    testWidgets('an account change narrows both, never just one', (
      tester,
    ) async {
      // The failure this guards is a chart that subtracts one account's
      // spending from every account's income and calls it savings.
      final repository = _ScriptedRepository(incomeCents: 100, totals: []);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(IncomeExpenseBars)))
              .read(analyticsAccountFilterProvider.notifier)
              .state =
          2;
      await tester.pumpAndSettle();

      expect(repository.askedIncome.last.accountId, 2);
      expect(repository.askedSpending.last.accountId, 2);
      expect(repository.askedIncome.last, repository.askedSpending.last);
    });

    testWidgets('names the period above the bars', (tester) async {
      await tester.pumpWidget(
        boot(_ScriptedRepository(incomeCents: 100, totals: [])),
      );
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsOneWidget);
    });
  });

  group('the states around the data', () {
    testWidgets('shows a spinner while either aggregate is in flight', (
      tester,
    ) async {
      final held = Completer<void>();
      addTearDown(() {
        if (!held.isCompleted) held.complete();
      });

      await tester.pumpWidget(
        boot(_ScriptedRepository(incomeCents: 100, hold: held)),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('a period with neither income nor spending says so', (
      tester,
    ) async {
      await tester.pumpWidget(boot(_ScriptedRepository()));
      await tester.pumpAndSettle();

      expect(
        find.text('No income or spending in this period.'),
        findsOneWidget,
      );
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('income alone still draws, with the whole lot as savings', (
      tester,
    ) async {
      await tester.pumpWidget(boot(_ScriptedRepository(incomeCents: 500000)));
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Net savings'), findsOneWidget);
      expect(find.text('Rs5,000.00'), findsOneWidget);
    });

    testWidgets('spending alone still draws, as overspending', (tester) async {
      await tester.pumpWidget(
        boot(_ScriptedRepository(totals: [total('Food', 500000)])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Overspent'), findsOneWidget);
    });

    testWidgets('a failing income query shows its own message', (tester) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            incomeFailure: const CacheFailure('Could not read the database.'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not read the database.'), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('a failing spending query does too', (tester) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            incomeCents: 500000,
            spendingFailure: const CacheFailure('Disk is full.'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Disk is full.'), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
    });
  });
}
