@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/presentation/providers/account_providers.dart';
import 'package:moneyora/features/accounts/presentation/widgets/account_drawer.dart';

/// The account panel FR-ACC-003 asks for, over a scripted account list.
///
/// The arithmetic behind the total is tested in
/// `account_totals_test.dart`; what is checked here is what a person can
/// actually read — that a balance is rendered in its own currency, and that
/// the number at the top says what it left out instead of quietly being wrong.
void main() {
  Account account({
    required int id,
    String name = 'Cash',
    int balanceCents = 0,
    String currency = 'LKR',
    AccountType type = AccountType.cash,
    bool includeInTotal = true,
  }) => Account(
    id: id,
    name: name,
    icon: 'wallet',
    initialBalanceDate: DateTime(2026),
    type: type,
    currency: currency,
    currentBalanceCents: balanceCents,
    includeInTotal: includeInTotal,
  );

  /// Builds the drawer open, with [accounts] behind it.
  ///
  /// Rendered as a Scaffold's drawer rather than bare, so the test exercises
  /// the widget in the position it actually occupies.
  Widget boot({
    List<Account>? accounts,
    Object? failure,
    bool hold = false,
    List<Account>? archivedToo,
  }) {
    Stream<List<Account>> streamOf(List<Account>? value) {
      if (hold) return const Stream<List<Account>>.empty();
      if (failure != null) return Stream<List<Account>>.error(failure);
      return Stream<List<Account>>.value(value ?? const []);
    }

    return ProviderScope(
      overrides: [
        accountsProvider(false).overrideWith((ref) => streamOf(accounts)),
        // The archived view is a different query, not a filter applied to the
        // first one — the datasource is what excludes archived rows.
        accountsProvider(true)
            .overrideWith((ref) => streamOf(archivedToo ?? accounts)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(drawer: AccountDrawer(), body: SizedBox()),
      ),
    );
  }

  Future<void> openDrawer(WidgetTester tester) async {
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
  }

  group('the account list', () {
    testWidgets('names each account and its balance', (tester) async {
      await tester.pumpWidget(
        boot(
          accounts: [
            account(id: 1, balanceCents: 125000),
            account(
              id: 2,
              name: 'Payment card',
              balanceCents: -75000,
              type: AccountType.creditCard,
            ),
          ],
        ),
      );
      await openDrawer(tester);

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Rs1,250.00'), findsOneWidget);
      expect(find.text('Payment card'), findsOneWidget);
      // A credit card owing money is ordinary, and the sign has to survive.
      expect(find.text('-Rs750.00'), findsOneWidget);
    });

    testWidgets('shows the total of the accounts it can add', (tester) async {
      await tester.pumpWidget(
        boot(
          accounts: [
            account(id: 1, balanceCents: 125000),
            account(id: 2, name: 'Bank', balanceCents: 40050),
          ],
        ),
      );
      await openDrawer(tester);

      expect(find.text('Total balance'), findsOneWidget);
      expect(find.text('Rs1,650.50'), findsOneWidget);
    });

    testWidgets('leaves an account out of the total when the user said so', (
      tester,
    ) async {
      // FR-ACC-002's Include-in-Total toggle. It still appears in the list —
      // it is real money, just not counted as yours.
      //
      // Two counted accounts rather than one, so the total is a figure no
      // single row also shows. With one, the total and that row render the
      // same string and the assertion cannot tell a sum from an echo.
      await tester.pumpWidget(
        boot(
          accounts: [
            account(id: 1, balanceCents: 125000),
            account(id: 2, name: 'Bank', balanceCents: 25000),
            account(
              id: 3,
              name: 'Household',
              balanceCents: 500000,
              includeInTotal: false,
            ),
          ],
        ),
      );
      await openDrawer(tester);

      expect(find.text('Household'), findsOneWidget);
      // Rs500,000 excluded: 125000 + 25000 only.
      expect(find.text('Rs1,500.00'), findsOneWidget);
      // And no note about currencies: the user chose this, so there is
      // nothing about the app's limits to explain.
      expect(find.textContaining('cannot convert'), findsNothing);
    });
  });

  group('a currency the app cannot convert', () {
    testWidgets('renders the balance in its own currency, not rupees', (
      tester,
    ) async {
      // E-25. Until FR-ACC-005 lands there is no conversion, so showing a
      // dollar balance with an Rs in front of it would state something false.
      await tester.pumpWidget(
        boot(
          accounts: [
            account(id: 1, balanceCents: 125000),
            account(
              id: 2,
              name: 'PayPal',
              balanceCents: 30000,
              currency: 'USD',
              type: AccountType.digitalWallet,
            ),
          ],
        ),
      );
      await openDrawer(tester);

      expect(find.text('USD 300.00'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
    });

    testWidgets('keeps it out of the total and says so', (tester) async {
      // Two rupee accounts, so the total is distinguishable from any one row.
      await tester.pumpWidget(
        boot(
          accounts: [
            account(id: 1, balanceCents: 125000),
            account(id: 2, name: 'Bank', balanceCents: 25000),
            account(
              id: 3,
              name: 'PayPal',
              balanceCents: 30000,
              currency: 'USD',
            ),
          ],
        ),
      );
      await openDrawer(tester);

      // The rupee accounts alone, and correct rather than approximate.
      expect(find.text('Rs1,500.00'), findsOneWidget);
      expect(
        find.textContaining('One account in another currency is not counted'),
        findsOneWidget,
      );
    });

    testWidgets('counts more than one of them in plain English', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(
          accounts: [
            account(id: 1, balanceCents: 125000),
            account(
              id: 2,
              name: 'PayPal',
              balanceCents: 30000,
              currency: 'USD',
            ),
            account(id: 3, name: 'Wise', balanceCents: 40000, currency: 'EUR'),
          ],
        ),
      );
      await openDrawer(tester);

      expect(
        find.textContaining('2 accounts in other currencies are not counted'),
        findsOneWidget,
      );
    });

    testWidgets('says nothing at all when every account is in rupees', (
      tester,
    ) async {
      // The note is a stated limit, not decoration. On an install that has
      // never seen another currency it should be invisible — and so should the
      // per-row currency label.
      await tester.pumpWidget(
        boot(accounts: [account(id: 1, balanceCents: 125000)]),
      );
      await openDrawer(tester);

      expect(find.textContaining('cannot convert'), findsNothing);
      expect(find.text('LKR'), findsNothing);
    });
  });

  group('the states that are not data', () {
    testWidgets('shows progress while the accounts are loading', (
      tester,
    ) async {
      await tester.pumpWidget(boot(hold: true));
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the failure it was given, not an invented one', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(failure: const CacheFailure('The database is locked.')),
      );
      await openDrawer(tester);

      expect(find.text('The database is locked.'), findsOneWidget);
    });

    testWidgets('survives having no accounts at all', (tester) async {
      // E-22 calls this state impossible — the seed makes a Cash account and
      // ArchiveAccount refuses to archive the last one. "Impossible" is a
      // claim about today's code, and an empty ListView would present as a
      // drawer that failed to load.
      await tester.pumpWidget(boot(accounts: const []));
      await openDrawer(tester);

      expect(find.text('No accounts yet.'), findsOneWidget);
      expect(find.text('Rs0.00'), findsOneWidget);
    });
  });

  group('archived accounts', () {
    Account archived({required int id, String name = 'Old bank'}) => Account(
      id: id,
      name: name,
      icon: 'bank',
      initialBalanceDate: DateTime(2026),
      isArchived: true,
    );

    testWidgets('are hidden until asked for', (tester) async {
      // FR-ACC-004 — hiding them from active views is the whole point.
      await tester.pumpWidget(
        boot(
          accounts: [account(id: 1, balanceCents: 125000)],
          archivedToo: [account(id: 1, balanceCents: 125000), archived(id: 2)],
        ),
      );
      await openDrawer(tester);

      expect(find.text('Old bank'), findsNothing);
      expect(find.text('Show archived'), findsOneWidget);
    });

    testWidgets('appear when the toggle is turned on, and say they are', (
      tester,
    ) async {
      // Reachable, or an archived account could never be restored — the
      // control that hides it would be one-way.
      await tester.pumpWidget(
        boot(
          accounts: [account(id: 1, balanceCents: 125000)],
          archivedToo: [account(id: 1, balanceCents: 125000), archived(id: 2)],
        ),
      );
      await openDrawer(tester);

      await tester.tap(find.text('Show archived'));
      await tester.pumpAndSettle();

      expect(find.text('Old bank'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
    });

    testWidgets('an archived account is not in the total', (tester) async {
      // AccountTotals ignores archived accounts, so switching the filter on
      // must not move the number at the top.
      await tester.pumpWidget(
        boot(
          accounts: [account(id: 1, balanceCents: 125000)],
          archivedToo: [
            account(id: 1, balanceCents: 125000),
            archived(id: 2).copyWith(currentBalanceCents: 900000),
          ],
        ),
      );
      await openDrawer(tester);

      await tester.tap(find.text('Show archived'));
      await tester.pumpAndSettle();

      expect(find.text('Rs1,250.00'), findsNWidgets(2));
      expect(find.text('Rs9,000.00'), findsOneWidget);
    });

    testWidgets('says why the archived list is empty, not just that it is', (
      tester,
    ) async {
      // The E-22 gap. Its table calls the accounts empty state impossible,
      // which is true of the default list and not of this one: turning the
      // filter on with nothing archived empties it. Two lists, two sentences,
      // per E-22's own rule.
      await tester.pumpWidget(
        boot(
          accounts: [account(id: 1, balanceCents: 125000)],
          archivedToo: const [],
        ),
      );
      await openDrawer(tester);

      await tester.tap(find.text('Show archived'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing archived'), findsOneWidget);
      // Not the "nothing yet" sentence, which would be wrong — they have an
      // account, it simply is not archived.
      expect(find.text('No accounts yet.'), findsNothing);
    });
  });
}
