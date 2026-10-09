@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/presentation/pages/credit_cards_page.dart';
import 'package:moneyora/features/accounts/presentation/providers/account_providers.dart';
import 'package:moneyora/injection.dart';

import 'large_text.dart';

/// The credit cards screen over scripted accounts. FR-ACC-009, E-43.
void main() {
  final today = DateTime(2026, 10, 9, 12);

  Account account({
    String name = 'Visa',
    AccountType type = AccountType.creditCard,
    int balance = -1250000,
    CreditCardTerms terms = const CreditCardTerms(
      limitCents: 5000000,
      statementDay: 20,
      dueDay: 5,
      aprBasisPoints: 2400,
    ),
  }) => Account(
    id: name.hashCode,
    name: name,
    icon: 'card',
    type: type,
    initialBalanceDate: DateTime(2026),
    currentBalanceCents: balance,
    creditCard: terms,
  );

  Widget boot(List<Account> accounts) => ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(() => today),
      accountsProvider(false).overrideWith((ref) => Stream.value(accounts)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: Routes.creditCards,
        routes: [
          GoRoute(
            path: Routes.creditCards,
            builder: (context, state) => const CreditCardsPage(),
          ),
          GoRoute(
            path: Routes.accountForm,
            builder: (context, state) =>
                Scaffold(body: Text('form for ${state.extra}')),
          ),
        ],
      ),
    ),
  );

  Future<void> open(WidgetTester tester, List<Account> accounts) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(boot(accounts));
    await tester.pumpAndSettle();
  }

  testWidgets('a card: owed of the limit, what is left, the days, and the '
      'interest', (tester) async {
    await open(tester, [
      account(),
      account(name: 'Cash', type: AccountType.cash),
    ]);

    expect(find.text('Visa'), findsOneWidget);
    // Cash is not a card.
    expect(find.text('Cash'), findsNothing);
    expect(find.text('Owed Rs12,500.00 of Rs50,000.00'), findsOneWidget);
    expect(find.text('Rs37,500.00 left to spend · 25% used'), findsOneWidget);
    expect(
      find.text('Statement 20 Oct · Payment due 5 Nov (in 27 days)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('At 24.00% a year, about Rs250.00 interest a month'),
      findsOneWidget,
    );
  });

  testWidgets('the payoff, answered as the payment is typed', (tester) async {
    await open(tester, [
      account(
        balance: -100000,
        terms: const CreditCardTerms(aprBasisPoints: 1200),
      ),
    ]);

    await tester.enterText(
      find.widgetWithText(TextField, 'If I pay each month'),
      '500',
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Paid off in 3 months, with about Rs15.25'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'If I pay each month'),
      '5',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('does not cover the interest'), findsOneWidget);
  });

  testWidgets('terms not entered say what to add', (tester) async {
    await open(tester, [account(terms: CreditCardTerms.none)]);

    expect(find.text('Owed Rs12,500.00'), findsOneWidget);
    expect(
      find.textContaining('Add the credit limit and the payment due day'),
      findsOneWidget,
    );
    expect(find.textContaining('Add the interest rate'), findsOneWidget);
    expect(find.text('If I pay each month'), findsNothing);
  });

  testWidgets('with no card, says how to add one, and opens the form on a '
      'card', (tester) async {
    await open(tester, [account(name: 'Cash', type: AccountType.cash)]);

    expect(find.text('No credit cards yet'), findsOneWidget);
    await tester.tap(find.text('Add a card'));
    await tester.pumpAndSettle();

    expect(find.text('form for AccountType.creditCard'), findsOneWidget);
  });

  testWidgets('holds at the largest font on a 320dp phone. SRS §4.1', (
    tester,
  ) async {
    useLargeTextOnSmallPhone(tester);
    await tester.pumpWidget(
      boot([account(name: 'A card with a long name', balance: -987654321)]),
    );
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('If I pay each month'), findsOneWidget);
  });
}
