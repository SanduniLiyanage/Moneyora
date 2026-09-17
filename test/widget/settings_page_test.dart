@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/domain/repositories/account_repository.dart';
import 'package:moneyora/features/settings/presentation/pages/settings_page.dart';
import 'package:moneyora/injection.dart';

/// The settings screen, driven the way a person drives it.
///
/// The repository is a fake; everything above it is real — the widgets, the
/// providers, and the actual `RecomputeAllAccountBalances` use case. What is
/// asserted is that the E-18 sweep runs when, and only when, the user asks
/// for it and confirms, and that a refusal reaches the screen in the
/// failure's own words.
class _FakeRepository implements AccountRepository {
  /// How many times the sweep was asked for.
  int sweeps = 0;

  /// Which single accounts were recomputed. The action must never do this:
  /// one transaction per account is what the sweep exists to avoid.
  final List<int> singles = [];

  /// Set to make the sweep fail, as a locked database would.
  Failure? failWith;

  @override
  Future<Either<Failure, Unit>> recomputeAllBalances() async {
    if (failWith case final failure?) return Left(failure);
    sweeps++;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, int>> recomputeBalance(int id) async {
    singles.add(id);
    return const Right(0);
  }

  @override
  Future<Either<Failure, int>> add(Account account) async => const Right(1);

  @override
  Future<Either<Failure, Unit>> update(Account account) async =>
      const Right(unit);

  @override
  Future<Either<Failure, Unit>> setArchived(
    int id, {
    required bool archived,
  }) async => const Right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => const Right(unit);

  @override
  Future<Either<Failure, int>> transactionCount(int id) async => const Right(0);

  @override
  Future<Either<Failure, List<Account>>> list({
    bool includeArchived = false,
  }) async => const Right([]);

  @override
  Stream<Either<Failure, List<Account>>> watch({
    bool includeArchived = false,
  }) => const Stream.empty();
}

void main() {
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());

  Widget boot() => ProviderScope(
    overrides: [
      accountRepositoryProvider.overrideWith((ref) async => repository),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const SettingsPage()),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester) async {
    await tester.tap(find.text('Recalculate account balances'));
    await tester.pumpAndSettle();
  }

  group('the recalculate-balances action', () {
    testWidgets('is offered, and does nothing until tapped', (tester) async {
      await open(tester);

      expect(find.text('Recalculate account balances'), findsOneWidget);
      expect(repository.sweeps, 0);
      expect(repository.singles, isEmpty);
    });

    testWidgets('asks before scanning every transaction', (tester) async {
      // E-18's addendum keeps this scan off the launch path because it reads
      // all of history; a stray tap on a settings row should not start it
      // either.
      await open(tester);
      await tapRow(tester);

      expect(find.text('Recalculate account balances?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.sweeps, 0);
      expect(find.text('Account balances recalculated.'), findsNothing);
    });

    testWidgets('runs the sweep once confirmed, and says so', (tester) async {
      await open(tester);
      await tapRow(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Recalculate'));
      await tester.pumpAndSettle();

      expect(repository.sweeps, 1);
      // One sweep in one transaction — never a per-account loop from here.
      expect(repository.singles, isEmpty);
      expect(find.text('Account balances recalculated.'), findsOneWidget);
    });

    testWidgets('shows the failure in its own words', (tester) async {
      repository.failWith = const CacheFailure('database is locked');
      await open(tester);
      await tapRow(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Recalculate'));
      await tester.pumpAndSettle();

      expect(repository.sweeps, 0);
      expect(find.text('database is locked'), findsOneWidget);
      expect(find.text('Account balances recalculated.'), findsNothing);
    });
  });
}
