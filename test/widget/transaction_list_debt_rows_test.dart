@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/presentation/pages/transaction_list_page.dart';
import 'package:moneyora/features/transactions/presentation/providers/transaction_providers.dart';

import 'large_text.dart';

/// A debt's money movement in an account's history: there, so the balance
/// can be explained, and changed only with its debt. FR-DBT-009, E-47.
void main() {
  final lent = Transaction(
    id: 41,
    accountId: 1,
    amountCents: 250000,
    type: TransactionType.transfer,
    transferDirection: TransferDirection.out,
    date: DateTime(2026, 10, 5),
    note: 'Lent to Nimal',
    debtId: 7,
  );

  Widget boot({bool dark = false}) => ProviderScope(
    overrides: [
      transactionsProvider.overrideWith((ref, filter) => Stream.value([lent])),
      entryAccountsProvider.overrideWith(
        (ref) => Stream.value(const [
          AccountOption(id: 1, name: 'Cash', balanceCents: 750000),
        ]),
      ),
      entryCategoriesProvider.overrideWith(
        (ref) => Stream.value(const <CategoryOption>[]),
      ),
    ],
    child: MaterialApp.router(
      theme: dark ? AppTheme.dark : AppTheme.light,
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const TransactionListPage(accountId: 1),
          ),
          GoRoute(
            path: Routes.debts,
            builder: (context, state) =>
                const Scaffold(body: Text('The debts screen')),
          ),
        ],
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();
  }

  testWidgets('reads as a debt, with what it was, as money out', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Debt'), findsOneWidget);
    expect(find.textContaining('Lent to Nimal'), findsOneWidget);
    expect(find.text('−Rs2,500.00'), findsWidgets);
  });

  testWidgets('opens Debts, where it is changed with its debt', (tester) async {
    await open(tester);

    await tester.tap(find.text('Debt'));
    await tester.pumpAndSettle();

    expect(find.text('The debts screen'), findsOneWidget);
  });

  testWidgets('held, offers no Delete of its own', (tester) async {
    await open(tester);

    await tester.longPress(find.text('Debt'));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsNothing);
    expect(find.text('The debts screen'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('holds at the largest font on a 320dp phone ($theme)', (
      tester,
    ) async {
      useLargeTextOnSmallPhone(tester);
      await tester.pumpWidget(boot(dark: dark));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Debt'), findsOneWidget);
    });

    testWidgets('at the largest font the amount goes under the name, which '
        'keeps the row ($theme)', (tester) async {
      // Beside the amount, with Roboto at 2x on 320dp, "Debt" broke as
      // "Deb/t" and its note lost all but "Lent to".
      useLargeTextOnSmallPhone(tester);
      await tester.pumpWidget(boot(dark: dark));
      await tester.pumpAndSettle();

      final row = find.byType(TransactionRow);
      final name = find.descendant(of: row, matching: find.text('Debt'));
      final amount = find.descendant(
        of: row,
        matching: find.text('−Rs2,500.00'),
      );
      expect(
        tester.getTopLeft(amount).dy,
        greaterThan(tester.getBottomLeft(name).dy - 1),
      );
      expect(isCut(tester, name), isFalse);
    });
  }
}
