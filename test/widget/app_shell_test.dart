@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/app.dart';
import 'package:moneyora/core/database/database_summary.dart';
import 'package:moneyora/core/theme/app_colors.dart';
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
      // 15 expense + 3 income, per FR-EXP-003 and FR-INC-002.
      expect(find.text('Categories'), findsOneWidget);
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
  });
}
