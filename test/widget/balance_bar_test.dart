@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/core/ports/calendar_settings.dart';
import 'package:moneyora/core/theme/app_colors.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/daily_total.dart';
import 'package:moneyora/features/analytics/domain/entities/period_selection.dart';
import 'package:moneyora/features/analytics/domain/entities/transfer_totals.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_period_summary.dart';
import 'package:moneyora/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:moneyora/features/analytics/presentation/widgets/balance_bar.dart';
import 'package:moneyora/injection.dart';

import 'large_text.dart';

/// The balance over the chosen period and account: income less expenses,
/// green when positive and red otherwise. FR-RPT-006.
void main() {
  final today = DateTime(2026, 9, 26, 12);
  final september = DateRange.month(2026, 9);

  CategoryTotal spent(int cents) => CategoryTotal(
    categoryId: 1,
    name: 'Food',
    color: '#eb6834',
    amountCents: cents,
  );

  const accounts = [
    AccountOption(id: 1, name: 'Cash', balanceCents: 0),
    AccountOption(id: 2, name: 'Card', balanceCents: 0),
  ];

  Widget boot(_Scripted repository, {int? accountId}) => ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(() => today),
      calendarSettingsProvider.overrideWith(
        (ref) => Stream.value(CalendarSettings.defaults),
      ),
      analyticsPeriodProvider.overrideWith(
        (ref) => PeriodSelection(period: AnalyticsPeriod.month, anchor: today),
      ),
      analyticsAccountFilterProvider.overrideWith((ref) => accountId),
      accountOptionsProvider.overrideWith((ref) => Stream.value(accounts)),
      getPeriodSummaryProvider.overrideWith(
        (ref) async => GetPeriodSummary(repository),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Padding(padding: EdgeInsets.all(16), child: BalanceBar()),
      ),
    ),
  );

  Color colourOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  AppColors colours(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(BalanceBar))).extension<AppColors>()!;

  testWidgets('more in than out: the balance, in green', (tester) async {
    await tester.pumpWidget(
      boot(
        _Scripted()
          ..income[september] = 101890000
          ..spending[september] = [spent(100265000)],
      ),
    );
    await tester.pumpAndSettle();

    // The reference app's own figures: 1,018,900 − 1,002,650.
    expect(find.text('+Rs16,250.00'), findsOneWidget);
    expect(colourOf(tester, '+Rs16,250.00'), colours(tester).income);
    expect(find.text('September 2026 · All accounts'), findsOneWidget);
    expect(find.text('In Rs1,018,900.00 · out Rs1,002,650.00'), findsOneWidget);
  });

  testWidgets('more out than in: the shortfall, in red', (tester) async {
    await tester.pumpWidget(
      boot(
        _Scripted()
          ..income[september] = 100000
          ..spending[september] = [spent(350000)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('−Rs2,500.00'), findsOneWidget);
    expect(colourOf(tester, '−Rs2,500.00'), colours(tester).expense);
  });

  testWidgets('nothing left over is red too', (tester) async {
    await tester.pumpWidget(
      boot(
        _Scripted()
          ..income[september] = 100000
          ..spending[september] = [spent(100000)],
      ),
    );
    await tester.pumpAndSettle();

    expect(colourOf(tester, 'Rs0.00'), colours(tester).expense);
  });

  testWidgets('names the one account it is for, and asks it alone', (
    tester,
  ) async {
    final repository = _Scripted()..income[september] = 5000;
    await tester.pumpWidget(boot(repository, accountId: 1));
    await tester.pumpAndSettle();

    expect(find.text('September 2026 · Cash'), findsOneWidget);
    expect(repository.accounts, everyElement(1));
  });

  group('a transfer, cash drawn from the card. FR-TRF-004', () {
    _Scripted drawn() => _Scripted()
      ..transfers[1] = const TransferTotals(inCents: 20000, outCents: 0)
      ..transfers[2] = const TransferTotals(inCents: 0, outCents: 20000);

    testWidgets('on the card: gone, in red', (tester) async {
      await tester.pumpWidget(boot(drawn(), accountId: 2));
      await tester.pumpAndSettle();

      expect(colourOf(tester, '−Rs200.00'), colours(tester).expense);
      expect(find.text('In Rs0.00 · out Rs200.00'), findsOneWidget);
    });

    testWidgets('in cash: arrived, in green', (tester) async {
      await tester.pumpWidget(boot(drawn(), accountId: 1));
      await tester.pumpAndSettle();

      expect(colourOf(tester, '+Rs200.00'), colours(tester).income);
      expect(find.text('In Rs200.00 · out Rs0.00'), findsOneWidget);
    });

    testWidgets('across every account: the legs cancel', (tester) async {
      await tester.pumpWidget(boot(drawn()));
      await tester.pumpAndSettle();

      expect(find.text('Rs0.00'), findsOneWidget);
      expect(find.text('In Rs0.00 · out Rs0.00'), findsOneWidget);
    });
  });

  testWidgets('a tap opens the period and account choices', (tester) async {
    await tester.pumpWidget(boot(_Scripted()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BalanceBar));
    await tester.pumpAndSettle();

    for (final label in ['Period', 'Account', 'Day', 'Week', 'Year', 'All']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('holds at the largest font on a 320dp phone. SRS §4.1', (
    tester,
  ) async {
    useLargeTextOnSmallPhone(tester);
    await tester.pumpWidget(
      boot(
        _Scripted()
          ..income[september] = 987654321
          ..spending[september] = [spent(123456789)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Balance'), findsOneWidget);
  });
}

class _Scripted implements AnalyticsRepository {
  /// Per account id.
  final Map<int, TransferTotals> transfers = {};

  @override
  Future<Either<Failure, TransferTotals>> transfersForPeriod(
    AnalyticsQuery query,
  ) async => Right(transfers[query.accountId] ?? TransferTotals.none);

  final Map<DateRange, List<CategoryTotal>> spending = {};
  final Map<DateRange, int> income = {};

  /// Which account each query was for.
  final List<int?> accounts = [];

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async {
    accounts.add(query.accountId);
    return Right(spending[query.range] ?? const []);
  }

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) async {
    accounts.add(query.accountId);
    return Right(income[query.range] ?? 0);
  }

  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, List<DailyTotal>>> dailySpendingTotals(
    AnalyticsQuery query,
  ) => throw UnimplementedError();
}
