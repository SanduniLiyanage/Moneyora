@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/app.dart';
import 'package:moneyora/core/database/database_summary.dart';
import 'package:moneyora/core/theme/app_colors.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/presentation/providers/account_providers.dart';
import 'package:moneyora/features/copilot/data/datasources/secure_llm_api_key_store.dart';
import 'package:moneyora/injection.dart';

/// Widget tests for the app shell: theming, routing, and the three states the
/// home screen can be in.
///
/// [databaseSummaryProvider] is overridden rather than driven by a real
/// database. Widget tests run in a fake-async zone where genuine file I/O never
/// completes, so pumping a real `sqflite` open just hangs — and the database
/// already has 24 unit tests of its own. What is worth testing here is the
/// thing those cannot reach: that each `AsyncValue` state renders something
/// sensible.
///
/// The one claim neither layer can make is that it works on a phone. That is
/// what the screen itself is for.
void main() {
  const ready = DatabaseSummary(
    schemaVersion: 1,
    accounts: 1,
    categories: 18,
    transactions: 0,
  );

  Widget bootApp(Override summaryOverride) =>
      ProviderScope(overrides: [summaryOverride], child: const MoneyoraApp());

  /// The whole app, with one account behind the accounts panel.
  ///
  /// The panel reads accounts through a use case that would open a real
  /// database, which never completes in a widget test's fake-async zone.
  Widget bootWithAccounts() => ProviderScope(
    overrides: [
      databaseSummaryProvider.overrideWith((ref) => ready),
      accountsProvider(false).overrideWith(
        (ref) => Stream.value([
          Account(
            id: 1,
            name: 'Cash',
            icon: 'wallet',
            initialBalanceDate: DateTime(2026),
            currentBalanceCents: 125000,
          ),
        ]),
      ),
    ],
    child: const MoneyoraApp(),
  );

  group('home screen states', () {
    testWidgets('shows a spinner while the database opens', (tester) async {
      // A Completer that is never completed holds the provider in its loading
      // state for as long as the test wants to look at it.
      final held = Completer<DatabaseSummary>();
      addTearDown(() => held.complete(ready));

      await tester.pumpWidget(
        bootApp(databaseSummaryProvider.overrideWith((ref) => held.future)),
      );
      // pump, not pumpAndSettle: a spinner animates forever and would never
      // settle.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows what is in the database once it opens', (tester) async {
      await tester.pumpWidget(
        bootApp(databaseSummaryProvider.overrideWith((ref) => ready)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Database ready'), findsOneWidget);
      // 15 expense + 3 income, per FR-EXP-003 and FR-INC-002. Scoped to the
      // summary card: the "Coming next" list below it links to the
      // categories screen under the same word.
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.text('Categories'),
        ),
        findsOneWidget,
      );
      expect(find.text('18'), findsOneWidget);
      expect(find.text('Schema version'), findsOneWidget);
    });

    testWidgets('explains itself when the database cannot be opened', (
      tester,
    ) async {
      // The realistic causes — a keychain entry that vanished, a migration
      // that failed — are indistinguishable from "the app is broken" unless
      // the screen says otherwise.
      await tester.pumpWidget(
        bootApp(
          databaseSummaryProvider.overrideWith(
            (ref) => Future<DatabaseSummary>.error(
              StateError('keychain unavailable'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not open the database'), findsOneWidget);
      expect(find.textContaining('keychain unavailable'), findsOneWidget);
    });
  });

  group('shell', () {
    Future<void> pumpReady(WidgetTester tester) async {
      await tester.pumpWidget(
        bootApp(databaseSummaryProvider.overrideWith((ref) => ready)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('applies the Moneyora theme rather than Flutter defaults', (
      tester,
    ) async {
      await pumpReady(tester);

      final context = tester.element(find.text('Moneyora'));
      final theme = Theme.of(context);

      expect(
        theme.extension<AppColors>(),
        isNotNull,
        reason: 'without AppColors every screen reading it crashes',
      );
      expect(theme.useMaterial3, isTrue);
    });

    testWidgets('navigates to a planned screen, which names its sprint', (
      tester,
    ) async {
      await pumpReady(tester);

      await tester.tap(find.text('Money Plan'));
      await tester.pumpAndSettle();

      // Stating the sprint makes an unbuilt screen read as planned work
      // rather than as a bug.
      expect(find.text('Arrives in Sprint 5.'), findsOneWidget);
    });

    testWidgets('reaches Settings from the app bar', (tester) async {
      await pumpReady(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Arrives in Sprint 7.'), findsOneWidget);
    });

    testWidgets('every screen opened from home can be left again', (
      tester,
    ) async {
      // `context.go` replaces the location instead of stacking on it, which
      // leaves a screen with no back arrow and a device back button that
      // exits the app. Every destination is checked, because the mistake is
      // per-call-site and one corrected navigation says nothing about the
      // next.
      for (final destination in const [
        'Ask Moneyora',
        'Money Plan',
        'Scan Receipt',
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseSummaryProvider.overrideWith((ref) => ready),
              // The Copilot screen asks the platform keychain whether a key
              // exists, and a platform channel never answers in a widget test.
              llmApiKeyStoreProvider.overrideWithValue(
                InMemoryLlmApiKeyStore(),
              ),
            ],
            child: const MoneyoraApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(destination));
        await tester.pumpAndSettle();

        expect(
          find.byType(BackButton),
          findsOneWidget,
          reason: '$destination opened with no way back',
        );

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.text('Database ready'), findsOneWidget);
      }
    });

    testWidgets('the accounts panel opens from the home screen', (
      tester,
    ) async {
      // FR-ACC-003 asks for the accounts to be reachable "from the main
      // screen". The panel belongs to the accounts feature and the home
      // screen must not import it, so `app_router.dart` composes the two —
      // which means this wiring is only ever exercised through the real
      // router, as it is here.
      await tester.pumpWidget(bootWithAccounts());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      expect(find.text('Total balance'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Rs1,250.00'), findsNWidgets(2));
    });

    testWidgets('the panel opens an empty form for a new account', (
      tester,
    ) async {
      await tester.pumpWidget(bootWithAccounts());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(find.text('New account'), findsOneWidget);
    });

    testWidgets('tapping an account opens it for editing', (tester) async {
      // The account travels as go_router's `extra`, which is untyped. This is
      // the only test that exercises that cast with a real Account in it.
      await tester.pumpWidget(bootWithAccounts());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();

      expect(find.text('Edit account'), findsOneWidget);
      // Filled in, rather than a blank form that would silently create a
      // second account on save.
      expect(find.widgetWithText(TextField, 'Cash'), findsOneWidget);
    });
  });
}
