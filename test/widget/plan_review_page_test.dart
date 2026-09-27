@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/daily_spending_reader.dart';
import 'package:moneyora/core/ports/income_reader.dart';
import 'package:moneyora/core/ports/monthly_spending_reader.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/money_plan/domain/entities/allocation_request.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_evaluation.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_mode.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/allocate_budget.dart';
import 'package:moneyora/features/money_plan/domain/usecases/classify_categories.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compute_category_statistics.dart';
import 'package:moneyora/features/money_plan/presentation/pages/plan_review_page.dart';
import 'package:moneyora/features/money_plan/presentation/providers/money_plan_providers.dart';
import 'package:moneyora/injection.dart';

import 'large_text.dart';

/// The review screen over the real engine and scripted ports.
///
/// The engine is tested stage by stage on its own; what is worth asserting
/// here is what the screen *shows* of a draft — every figure with its
/// provenance — and how it reads each of the states beneath it.

class _ScriptedSpending implements MonthlySpendingReader {
  _ScriptedSpending({this.rows = const [], this.failure, this.hold});

  /// Not final: the sample-data tests put history in once it is loaded.
  List<MonthlySpending> rows;
  final Failure? failure;
  final Completer<void>? hold;

  @override
  Future<Either<Failure, List<MonthlySpending>>> monthlySpendingByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    if (hold != null) await hold!.future;
    if (failure case final f?) return Left(f);
    return Right(rows);
  }
}

/// The previous plan, for FR-PLN-014's carry-over; nothing else answers.
class _ScriptedPlans implements MoneyPlanRepository {
  _ScriptedPlans(this.previous);

  final MoneyPlan? previous;

  @override
  Future<Either<Failure, MoneyPlan?>> getLatestEndingBefore(
    DateTime day,
  ) async => Right(previous);

  @override
  Future<Either<Failure, Unit>> activate(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> recomputeSpent(int planId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Set<int>>> recordAlertLevels(
    List<AlertLevelChange> changes,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations,
  ) => throw UnimplementedError();

  @override
  Stream<Either<Failure, MoneyPlan?>> watchActive() =>
      throw UnimplementedError();

  @override
  Stream<Either<Failure, List<MoneyPlan>>> watchAll() =>
      throw UnimplementedError();
}

class _ScriptedIncome implements IncomeReader {
  _ScriptedIncome({this.income = 0});

  final int income;

  @override
  Future<Either<Failure, int>> totalIncome({
    required DateTime from,
    required DateTime to,
  }) async => Right(income);
}

/// Days of spending, as the heatmap's query would give them. FR-PLN-006.
class _ScriptedDays implements DailySpendingReader {
  _ScriptedDays([this.rows = const []]);

  final List<DailySpending> rows;

  @override
  Future<Either<Failure, List<DailySpending>>> dailySpending({
    required DateTime from,
    required DateTime to,
  }) async => Right(rows);
}

void main() {
  final now = DateTime(2026, 9, 13);
  final halfYear = LookbackWindow.before(now);
  final twelveMonths = LookbackWindow.before(now, months: 12);
  final october = PlanPeriod.month(2026, 10);

  /// [amounts] oldest first, one per month of [window], zero rows skipped.
  List<MonthlySpending> series(
    LookbackWindow window,
    int id,
    String name,
    List<int> amounts,
  ) => [
    for (var i = 0; i < window.months; i++)
      if (amounts[i] > 0)
        MonthlySpending(
          categoryId: id,
          name: name,
          month: window.monthStarts[i],
          amountCents: amounts[i],
          transactionCount: 1,
        ),
  ];

  /// Bills flat (Fixed), Car climbing (rising), Pets once (Low).
  List<MonthlySpending> shaped(LookbackWindow window) => [
    ...series(window, 1, 'Bills', List.filled(window.months, 4500000)),
    ...series(window, 2, 'Car', [
      for (var i = 0; i < window.months; i++) 1000000 + i * 200000,
    ]),
    ...series(window, 3, 'Pets', [
      for (var i = 0; i < window.months; i++) i == 1 ? 200000 : 0,
    ]),
  ];

  Widget boot(
    _ScriptedSpending spending, {
    required AllocationRequest request,
    int income = 0,
    MoneyPlan? previous,
    List<DailySpending> days = const [],
    DevSeedLoader? seed,
  }) => ProviderScope(
    overrides: [
      if (seed != null) devSeedLoaderProvider.overrideWith(() => seed),
      dailySpendingReaderProvider.overrideWith(
        (ref) async => _ScriptedDays(days),
      ),
      allocateBudgetProvider.overrideWith(
        (ref) async => AllocateBudget(
          ClassifyCategories(ComputeCategoryStatistics(spending)),
          _ScriptedIncome(income: income),
          plans: _ScriptedPlans(previous),
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: PlanReviewPage(request: request),
    ),
  );

  group('spending patterns. FR-PLN-006', () {
    List<DailySpending> everyDay(LookbackWindow window, int weekend) => [
      for (
        var d = window.from;
        !d.isAfter(window.to);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        DailySpending(
          day: d,
          amountCents:
              d.weekday == DateTime.saturday || d.weekday == DateTime.sunday
              ? weekend
              : 1000,
        ),
    ];

    Future<void> review(WidgetTester tester, List<DailySpending> days) async {
      await tester.pumpWidget(
        boot(
          _ScriptedSpending(rows: shaped(halfYear)),
          request: AllocationRequest(period: october, lookback: halfYear),
          days: days,
        ),
      );
      await tester.pumpAndSettle();
      // Below the categories: the figures first, what they show after.
      await tester.scrollUntilVisible(find.text('Spending patterns'), 200);
      await tester.pumpAndSettle();
    }

    testWidgets('the whole review holds at the largest font on a 320dp '
        'phone. SRS §4.1', (tester) async {
      useLargeTextOnSmallPhone(tester);
      await tester.pumpWidget(
        boot(
          _ScriptedSpending(rows: shaped(halfYear)),
          request: AllocationRequest(period: october, lookback: halfYear),
          days: everyDay(halfYear, 3000),
        ),
      );
      await tester.pumpAndSettle();

      await scrollToEnd(tester);
      expect(find.text('Spending patterns'), findsOneWidget);
    });

    testWidgets('names a weekend habit with its figures', (tester) async {
      await review(tester, everyDay(halfYear, 3000));

      expect(find.text('Spending patterns'), findsOneWidget);
      expect(
        find.textContaining('Weekends cost 200% more a day than weekdays'),
        findsOneWidget,
      );
    });

    testWidgets('says steady when nothing stands out', (tester) async {
      await review(tester, everyDay(halfYear, 1000));

      expect(find.textContaining('Steady across the week'), findsOneWidget);
    });

    testWidgets('says when there is too little to go on', (tester) async {
      await review(tester, const []);

      expect(
        find.text('Too little spending in these months to see a pattern yet.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a figure sits at the right of its row on a 320dp phone', (
    tester,
  ) async {
    // Found on the emulator: split evenly with its label, the total sat
    // mid-card and a long category name broke mid-word.
    tester.view
      ..physicalSize = const Size(960, 1920)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      boot(
        _ScriptedSpending(rows: shaped(halfYear)),
        request: AllocationRequest(period: october, lookback: halfYear),
      ),
    );
    await tester.pumpAndSettle();

    final totalRow = find
        .ancestor(of: find.text('Total'), matching: find.byType(Row))
        .first;
    final amount = find
        .descendant(of: totalRow, matching: find.byType(Text))
        .last;
    // 320 less the list's 16dp padding, the card's 4dp margin and its 16dp
    // padding.
    expect(tester.getTopRight(amount).dx, closeTo(284, 1));
  });

  testWidgets('spins while the engine works', (tester) async {
    final hold = Completer<void>();
    await tester.pumpWidget(
      boot(
        _ScriptedSpending(hold: hold),
        request: AllocationRequest(period: october, lookback: halfYear),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    hold.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows every category with its figure, class, confidence '
      'and factors', (tester) async {
    await tester.pumpWidget(
      boot(
        _ScriptedSpending(rows: shaped(halfYear)),
        request: AllocationRequest(period: october, lookback: halfYear),
      ),
    );
    await tester.pumpAndSettle();

    // The header: period, mode, total, lookback.
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.textContaining('31 days'), findsOneWidget);
    expect(find.textContaining('From your spending history'), findsOneWidget);
    expect(find.text('From the last 6 months.'), findsOneWidget);

    // Bills: Fixed, its flat average, no factors.
    expect(find.text('Bills'), findsOneWidget);
    expect(find.text('Rs45,000.00'), findsWidgets);
    expect(find.text('Fixed'), findsOneWidget);
    expect(find.text('Rs45,000.00 a month'), findsOneWidget);

    // Car: Variable and rising, so the trend factor is stated.
    expect(find.text('Car'), findsOneWidget);
    expect(find.textContaining('×1.08 rising'), findsOneWidget);

    // Pets: one month of data — Low, and the reason says so.
    expect(find.text('Pets'), findsOneWidget);
    expect(find.text('Low confidence'), findsOneWidget);
    expect(find.textContaining('1 month of data'), findsOneWidget);

    // Daily allowance on every card. FR-PLN-009.
    expect(find.textContaining(' a day'), findsNWidgets(3));
  });

  testWidgets('states the E-07 cap as the reason when the lookback holds '
      'the confidence down', (tester) async {
    // Twelve steady months would be High on the data; the window caps it.
    await tester.pumpWidget(
      boot(
        _ScriptedSpending(rows: shaped(twelveMonths)),
        request: AllocationRequest(period: october, lookback: twelveMonths),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Medium confidence'), findsWidgets);
    expect(
      find.text('Capped at Medium: 12 months of history, 24 needed for High'),
      findsOneWidget,
    );
  });

  testWidgets('a suggested total shows income and savings', (tester) async {
    await tester.pumpWidget(
      boot(
        _ScriptedSpending(rows: shaped(halfYear)),
        request: AllocationRequest(
          period: october,
          lookback: halfYear,
          mode: const BudgetMode.suggested(savingsTargetPct: 10),
        ),
        income: 6 * 18000000,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Rs180,000.00'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Rs18,000.00'), findsOneWidget);
    expect(find.textContaining('saving 10%'), findsOneWidget);
  });

  testWidgets('a user total is the total shown', (tester) async {
    await tester.pumpWidget(
      boot(
        _ScriptedSpending(rows: shaped(halfYear)),
        request: AllocationRequest(
          period: october,
          lookback: halfYear,
          mode: const BudgetMode.total(10000000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rs100,000.00'), findsOneWidget);
    expect(find.textContaining('Your total'), findsOneWidget);
  });

  group('sample data, with nothing to plan from (debug builds)', () {
    Future<_ScriptedSpending> empty(
      WidgetTester tester,
      _ScriptedSeed seed,
    ) async {
      final spending = _ScriptedSpending();
      await tester.pumpWidget(
        boot(
          spending,
          request: AllocationRequest(period: october, lookback: halfYear),
          seed: seed,
        ),
      );
      await tester.pumpAndSettle();
      return spending;
    }

    testWidgets('asks first, and cancelling loads nothing', (tester) async {
      final seed = _ScriptedSeed(const SampleDataLoad(written: 1234));
      await empty(tester, seed);

      await tester.tap(find.text('Try it with sample data'));
      await tester.pumpAndSettle();
      expect(find.text('Load sample data?'), findsOneWidget);
      expect(find.textContaining('added once'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(seed.loads, 0);
    });

    testWidgets('loads, says how much, and plans from it', (tester) async {
      final seed = _ScriptedSeed(const SampleDataLoad(written: 1234));
      final spending = await empty(tester, seed);
      seed.onLoad = () => spending.rows = shaped(halfYear);

      await tester.tap(find.text('Try it with sample data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();

      expect(seed.loads, 1);
      expect(find.text('Added 1234 sample transactions.'), findsOneWidget);
      expect(find.text('Nothing to plan from yet'), findsNothing);
      expect(find.text('Bills'), findsOneWidget);
    });

    testWidgets('says so rather than loading it twice', (tester) async {
      final seed = _ScriptedSeed(const SampleDataLoad(written: 0));
      await empty(tester, seed);

      await tester.tap(find.text('Try it with sample data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The sample data is already loaded'),
        findsOneWidget,
      );
    });
  });

  testWidgets('with no history it says so, rather than showing an empty '
      'list', (tester) async {
    await tester.pumpWidget(
      boot(
        _ScriptedSpending(),
        request: AllocationRequest(period: october, lookback: halfYear),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing to plan from yet'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets("a refused request shows the use case's own sentence", (
    tester,
  ) async {
    final inverted = PlanPeriod(
      from: DateTime(2026, 10, 31),
      to: DateTime(2026, 10),
    );
    await tester.pumpWidget(
      boot(
        _ScriptedSpending(rows: shaped(halfYear)),
        request: AllocationRequest(period: inverted, lookback: halfYear),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('The start of the plan is after its end.'),
      findsOneWidget,
    );
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('a failure beneath shows its message', (tester) async {
    await tester.pumpWidget(
      boot(
        _ScriptedSpending(failure: const CacheFailure('disk is full')),
        request: AllocationRequest(period: october, lookback: halfYear),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('disk is full'), findsOneWidget);
  });

  testWidgets('says what the previous plan carried over, on the header and '
      'on the card', (tester) async {
    // FR-PLN-014's Carry Over, arriving: September carried 3,000 on Bills.
    final september = MoneyPlan(
      id: 1,
      name: 'September',
      period: PlanPeriod.month(2026, 9),
      totalBudgetCents: 0,
      isActive: false,
      allocations: const [
        PlanAllocation(
          categoryId: 1,
          allocatedCents: 4500000,
          spentCents: 4800000,
          carryOverCents: 300000,
          confidence: ConfidenceLevel.high,
        ),
      ],
    );
    await tester.pumpWidget(
      boot(
        _ScriptedSpending(rows: shaped(halfYear)),
        request: AllocationRequest(period: october, lookback: halfYear),
        previous: september,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Carried over from September'), findsOneWidget);
    expect(find.text('-Rs3,000.00'), findsOneWidget);
    expect(find.text('Rs42,000.00'), findsOneWidget, reason: '45,000 − 3,000');
    expect(find.textContaining('−Rs3,000.00 carried over'), findsOneWidget);
  });
}

/// The loader with its outcome scripted: the real one opens a database.
class _ScriptedSeed extends DevSeedLoader {
  _ScriptedSeed(this.outcome);

  final SampleDataLoad outcome;
  int loads = 0;

  /// What loading puts on the phone, for the draft generated after it.
  void Function()? onLoad;

  @override
  Future<SampleDataLoad?> load() async {
    loads++;
    onLoad?.call();
    return outcome;
  }
}
