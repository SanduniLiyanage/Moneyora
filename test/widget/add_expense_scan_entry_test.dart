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
import 'package:moneyora/features/transactions/presentation/pages/add_transaction_page.dart';
import 'package:moneyora/features/transactions/presentation/providers/transaction_providers.dart';

/// FR-RCP-001's second entry point: the scanner from the add-expense flow.
///
/// Its own file rather than a case in `transactions_flow_test.dart`,
/// because that suite boots on a plain `MaterialApp` and the button
/// navigates by route — it needs a router with `/scan` in it.
void main() {
  const categories = [
    CategoryOption(
      id: 1,
      name: 'Food',
      icon: 'basket',
      colorHex: '#00aa00',
      isExpense: true,
    ),
    CategoryOption(
      id: 2,
      name: 'Salary',
      icon: 'cash',
      colorHex: '#c98500',
      isExpense: false,
    ),
  ];
  const accounts = [AccountOption(id: 1, name: 'Cash', balanceCents: 0)];

  final edited = Transaction(
    id: 5,
    accountId: 1,
    categoryId: 1,
    type: TransactionType.expense,
    amountCents: 50000,
    date: DateTime(2026, 9, 1),
  );

  Widget boot({Transaction? initial}) => ProviderScope(
    overrides: [
      entryCategoriesProvider.overrideWith(
        (ref) => Stream<List<CategoryOption>>.value(categories),
      ),
      entryAccountsProvider.overrideWith(
        (ref) => Stream<List<AccountOption>>.value(accounts),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => AddTransactionPage(initial: initial),
          ),
          GoRoute(
            path: Routes.scanReceipt,
            builder: (context, state) => const Scaffold(body: Text('scanner')),
          ),
        ],
      ),
    ),
  );

  final scanButton = find.byTooltip('Scan Receipt');

  testWidgets('a new expense offers the scanner, which opens on tap', (
    tester,
  ) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    expect(find.text('New expense'), findsOneWidget);
    expect(scanButton, findsOneWidget);

    await tester.tap(scanButton);
    await tester.pumpAndSettle();
    expect(find.text('scanner'), findsOneWidget);
  });

  testWidgets('an income does not: a receipt is never one', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();

    expect(find.text('New income'), findsOneWidget);
    expect(scanButton, findsNothing);
  });

  testWidgets('an edit does not: the row already exists', (tester) async {
    await tester.pumpWidget(boot(initial: edited));
    await tester.pumpAndSettle();

    expect(find.text('Edit expense'), findsOneWidget);
    expect(scanButton, findsNothing);
  });
}
