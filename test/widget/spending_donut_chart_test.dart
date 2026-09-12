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
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_by_category.dart';
import 'package:moneyora/features/analytics/presentation/widgets/spending_donut_chart.dart';
import 'package:moneyora/injection.dart';

/// The donut chart over a scripted repository and category reader, with no
/// real database at all — the same shape `copilot_screen_test.dart` uses for
/// its scripted `LlmRepository`.
class _FakeAnalyticsRepository implements AnalyticsRepository {
  _FakeAnalyticsRepository(this.spendingResult);

  final Either<Failure, List<CategoryTotal>> spendingResult;

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    DateRange range,
  ) async => spendingResult;

  @override
  Future<Either<Failure, int>> incomeForPeriod(DateRange range) =>
      throw UnimplementedError();
}

class _FakeCategoryReader implements CategoryReader {
  _FakeCategoryReader(this.options);

  final List<CategoryOption> options;

  @override
  Stream<Either<Failure, List<CategoryOption>>> watchAll() =>
      Stream.value(Right(options));
}

void main() {
  Widget boot({
    required Either<Failure, List<CategoryTotal>> spendingResult,
    List<CategoryOption> categories = const [],
    int transactionsEver = 5,
    Completer<void>? hold,
  }) => ProviderScope(
    overrides: [
      databaseSummaryProvider.overrideWith(
        (ref) async => DatabaseSummary(
          schemaVersion: 1,
          accounts: 1,
          categories: categories.length,
          transactions: transactionsEver,
        ),
      ),
      categoryReaderProvider.overrideWith(
        (ref) async => _FakeCategoryReader(categories),
      ),
      getSpendingByCategoryProvider.overrideWith((ref) async {
        if (hold != null) await hold.future;
        return GetSpendingByCategory(_FakeAnalyticsRepository(spendingResult));
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: SpendingDonutChart()),
    ),
  );

  CategoryTotal food(int cents) => CategoryTotal(
    categoryId: 1,
    name: 'Food',
    color: '#eb6834',
    amountCents: cents,
  );

  group('while loading', () {
    testWidgets('shows a spinner rather than an empty card', (tester) async {
      final held = Completer<void>();
      addTearDown(() {
        if (!held.isCompleted) held.complete();
      });

      await tester.pumpWidget(
        boot(spendingResult: Right([food(1000)]), hold: held),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(PieChart), findsNothing);
    });
  });

  group('with data', () {
    testWidgets('draws the chart and lists each category with its amount', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          spendingResult: Right([
            food(342000),
            const CategoryTotal(
              categoryId: 2,
              name: 'Transport',
              color: '#2a78d6',
              amountCents: 114000,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PieChart), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Rs3,420.00'), findsOneWidget);
      expect(find.text('Rs1,140.00'), findsOneWidget);
    });

    testWidgets('folds every category past the sixth into "Other"', (
      tester,
    ) async {
      final totals = [
        for (var i = 1; i <= 8; i++)
          CategoryTotal(
            categoryId: i,
            name: 'Category $i',
            color: '#2a78d6',
            amountCents: (9 - i) * 1000,
          ),
      ];

      await tester.pumpWidget(boot(spendingResult: Right(totals)));
      await tester.pumpAndSettle();

      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Category 7'), findsNothing);
      expect(find.text('Category 8'), findsNothing);
      expect(find.text('Category 1'), findsOneWidget);
      expect(find.text('Category 6'), findsOneWidget);
    });
  });

  group('when there is nothing to show', () {
    testWidgets('a brand new user is invited to add their first expense', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(spendingResult: const Right([]), transactionsEver: 0),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('once you have added an expense'),
        findsOneWidget,
      );
      expect(find.byType(PieChart), findsNothing);
    });

    testWidgets('an existing user with a quiet month is told about the '
        'period, not invited to start over', (tester) async {
      // E-22: conflating the two is "the familiar bug of telling a user with
      // four hundred transactions to add their first expense".
      await tester.pumpWidget(
        boot(spendingResult: const Right([]), transactionsEver: 400),
      );
      await tester.pumpAndSettle();

      expect(find.text('No spending in this period.'), findsOneWidget);
      expect(
        find.textContaining('once you have added an expense'),
        findsNothing,
      );
    });
  });

  group('when the query fails', () {
    testWidgets('shows the failure\'s own message', (tester) async {
      await tester.pumpWidget(
        boot(
          spendingResult: const Left(
            CacheFailure('Could not read the database.'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not read the database.'), findsOneWidget);
      expect(find.byType(PieChart), findsNothing);
    });
  });
}
