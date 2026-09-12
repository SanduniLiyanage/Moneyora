@TestOn('vm')
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/database/database_summary.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/period_selection.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_by_category.dart';
import 'package:moneyora/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:moneyora/features/analytics/presentation/widgets/account_filter.dart';
import 'package:moneyora/features/analytics/presentation/widgets/spending_donut_chart.dart';
import 'package:moneyora/injection.dart';

/// FR-RPT-003's filter through the chart it narrows.
///
/// As with the period selector, what is worth asserting is not which item the
/// dropdown shows — it is *which query was asked for* afterwards, and that
/// only exists once the chart beneath it watches the same providers the real
/// screen does.

/// Records every query it is asked for, in order.
class _RecordingRepository implements AnalyticsRepository {
  final List<AnalyticsQuery> asked = [];

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async {
    asked.add(query);
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
}

class _FakeCategoryReader implements CategoryReader {
  @override
  Stream<Either<Failure, List<CategoryOption>>> watchAll() =>
      Stream.value(const Right([]));
}

class _FakeAccountReader implements AccountReader {
  _FakeAccountReader(this.accounts);

  final List<AccountOption> accounts;

  @override
  Stream<Either<Failure, List<AccountOption>>> watchAll() =>
      Stream.value(Right(accounts));
}

/// An account reader that fails, so the dropdown's own error path is exercised
/// rather than assumed.
class _FailingAccountReader implements AccountReader {
  @override
  Stream<Either<Failure, List<AccountOption>>> watchAll() =>
      Stream.value(const Left(CacheFailure('Could not read your accounts.')));
}

void main() {
  final anchor = DateTime(2026, 9, 9);

  const cash = AccountOption(id: 1, name: 'Cash', balanceCents: 500000);
  const card = AccountOption(id: 2, name: 'Payment card', balanceCents: 250000);

  late _RecordingRepository repository;

  setUp(() => repository = _RecordingRepository());

  Widget boot({List<AccountOption> accounts = const [cash, card]}) =>
      ProviderScope(
        overrides: [
          analyticsPeriodProvider.overrideWith(
            (ref) => PeriodSelection.monthOf(anchor),
          ),
          databaseSummaryProvider.overrideWith(
            (ref) async => const DatabaseSummary(
              schemaVersion: 1,
              accounts: 2,
              categories: 0,
              transactions: 5,
            ),
          ),
          categoryReaderProvider.overrideWith(
            (ref) async => _FakeCategoryReader(),
          ),
          accountReaderProvider.overrideWith(
            (ref) async => _FakeAccountReader(accounts),
          ),
          getSpendingByCategoryProvider.overrideWith(
            (ref) async => GetSpendingByCategory(repository),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SpendingDonutChart()),
        ),
      );

  int? filterOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SpendingDonutChart)))
          .read(analyticsAccountFilterProvider);

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButton<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  group('what it opens on', () {
    testWidgets('All Accounts, so the home-screen summary omits nothing', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      expect(find.text(allAccountsLabel), findsOneWidget);
      expect(filterOf(tester), isNull);
      expect(repository.asked.single.isAllAccounts, isTrue);
    });

    testWidgets('offers All Accounts plus every account. FR-RPT-003', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<int?>));
      await tester.pumpAndSettle();

      expect(find.text('Cash'), findsWidgets);
      expect(find.text('Payment card'), findsWidgets);
      expect(find.text(allAccountsLabel), findsWidgets);
    });
  });

  group('choosing one account', () {
    testWidgets('narrows the query to that account id', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      await choose(tester, 'Payment card');

      expect(filterOf(tester), card.id);
      expect(repository.asked.last.accountId, card.id);
      expect(repository.asked.last.isAllAccounts, isFalse);
    });

    testWidgets('keeps the period it was already showing', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      final periodBefore = repository.asked.single.range;

      await choose(tester, 'Cash');

      expect(repository.asked.last.range, periodBefore);
      expect(repository.asked.last.accountId, cash.id);
    });

    testWidgets('switching period keeps the account', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      await choose(tester, 'Cash');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Year'));
      await tester.pumpAndSettle();

      expect(repository.asked.last.accountId, cash.id);
      expect(repository.asked.last.range, DateRange.year(2026));
    });

    testWidgets('going back to All Accounts widens it again', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      await choose(tester, 'Cash');

      await choose(tester, allAccountsLabel);

      expect(filterOf(tester), isNull);
      expect(repository.asked.last.isAllAccounts, isTrue);
    });

    testWidgets('re-queries once per change, not once per rebuild', (
      tester,
    ) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();
      await choose(tester, 'Cash');
      await tester.pump();
      await tester.pump();

      expect(repository.asked.length, 2);
      expect(repository.asked.first.isAllAccounts, isTrue);
      expect(repository.asked.last.accountId, cash.id);
    });
  });

  group('when the account list is awkward', () {
    testWidgets('no accounts at all still offers All Accounts', (tester) async {
      await tester.pumpWidget(boot(accounts: const []));
      await tester.pumpAndSettle();

      expect(find.text(allAccountsLabel), findsOneWidget);
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('an id that names no account falls back to All Accounts', (
      tester,
    ) async {
      // Archiving or deleting the filtered account leaves the state holding an
      // id the dropdown has no item for, which is an assertion failure rather
      // than a visible bug — and "all accounts" is also the honest reading,
      // since the filtered one is gone.
      await tester.pumpWidget(boot(accounts: const [cash]));
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(SpendingDonutChart)))
              .read(analyticsAccountFilterProvider.notifier)
              .state =
          card.id;
      await tester.pumpAndSettle();

      expect(filterOf(tester), isNull);
      expect(find.text(allAccountsLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing account read still draws the chart', (tester) async {
      // The accounts are the filter's options, not the chart's data. Losing
      // them must not take the spending breakdown down with them.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsPeriodProvider.overrideWith(
              (ref) => PeriodSelection.monthOf(anchor),
            ),
            databaseSummaryProvider.overrideWith(
              (ref) async => const DatabaseSummary(
                schemaVersion: 1,
                accounts: 0,
                categories: 0,
                transactions: 5,
              ),
            ),
            categoryReaderProvider.overrideWith(
              (ref) async => _FakeCategoryReader(),
            ),
            accountReaderProvider.overrideWith(
              (ref) async => _FailingAccountReader(),
            ),
            getSpendingByCategoryProvider.overrideWith(
              (ref) async => GetSpendingByCategory(repository),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: SpendingDonutChart()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PieChart), findsOneWidget);
      expect(find.text(allAccountsLabel), findsOneWidget);
    });
  });
}
