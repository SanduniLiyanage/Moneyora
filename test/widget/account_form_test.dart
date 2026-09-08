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
import 'package:moneyora/features/accounts/presentation/pages/account_form_page.dart';
import 'package:moneyora/injection.dart';

/// The account form, driven the way a person drives it.
///
/// The repository is a fake; everything above it is real — the widgets, the
/// providers, and the actual `AddAccount` and `UpdateAccount` use cases with
/// their validation. That is the point: the messages asserted here are the use
/// case's own, so a rule cannot drift between the form and the thing that
/// enforces it.
class _FakeRepository implements AccountRepository {
  final List<Account> added = [];
  final List<Account> updated = [];

  /// Set to make the next write fail, as a locked database would.
  Failure? failWith;

  @override
  Future<Either<Failure, int>> add(Account account) async {
    if (failWith case final failure?) return Left(failure);
    added.add(account);
    return const Right(7);
  }

  @override
  Future<Either<Failure, Unit>> update(Account account) async {
    if (failWith case final failure?) return Left(failure);
    updated.add(account);
    return const Right(unit);
  }

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

  @override
  Future<Either<Failure, int>> recomputeBalance(int id) async => const Right(0);

  @override
  Future<Either<Failure, Unit>> recomputeAllBalances() async =>
      const Right(unit);
}

void main() {
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());

  /// Gives the form a viewport tall enough to hold all of it at once.
  ///
  /// The default 800x600 is shorter than this form, and a `ListView` builds
  /// lazily — so the Save button below the fold does not exist to be tapped,
  /// and every test would be scrolling before it could assert anything. A
  /// phone scrolls; a test asserting on validation messages should not have to.
  void useTallViewport(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Account existing() => Account(
    id: 4,
    name: 'Commercial Bank',
    icon: 'bank',
    type: AccountType.bank,
    currency: 'LKR',
    initialBalanceCents: 250000,
    currentBalanceCents: 812345,
    initialBalanceDate: DateTime(2026, 2, 3),
    includeInTotal: false,
  );

  Widget boot({Account? initial}) => ProviderScope(
    overrides: [
      accountRepositoryProvider.overrideWith((ref) async => repository),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: AccountFormPage(initial: initial),
    ),
  );

  /// Pumps the form with the whole of it on screen.
  Future<void> open(WidgetTester tester, {Account? initial}) async {
    useTallViewport(tester);
    await tester.pumpWidget(boot(initial: initial));
    await tester.pumpAndSettle();
  }

  group('creating an account', () {
    testWidgets('writes what was typed', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'Cash in hand');
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(repository.added, hasLength(1));
      expect(repository.added.single.name, 'Cash in hand');
      expect(repository.added.single.id, isNull);
    });

    testWidgets('refuses an empty name with the use case\'s own words', (
      tester,
    ) async {
      // AddAccount.validate owns this sentence. Asserting on it here is what
      // proves the form did not invent a second copy of the rule.
      await open(tester);

      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(find.text('Give the account a name.'), findsOneWidget);
      expect(repository.added, isEmpty);
    });

    testWidgets('says nothing about the name before Save is pressed', (
      tester,
    ) async {
      // Shouting at an empty field the user has not reached yet is how a form
      // reads as hostile.
      await open(tester);

      expect(find.text('Give the account a name.'), findsNothing);
    });

    testWidgets('refuses a currency that is not three letters', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'Wallet');
      await tester.enterText(find.byType(TextField).last, 'US');
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(
        find.text('Use a three-letter currency code, like LKR.'),
        findsOneWidget,
      );
      expect(repository.added, isEmpty);
    });

    testWidgets('keeps a negative opening balance, for a card that owes', (
      tester,
    ) async {
      // Signed, unlike a transaction amount. A credit card legitimately opens
      // owing money, and AddAccount.validate deliberately does not check the
      // sign.
      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'Visa');
      await tester.enterText(find.byType(TextField).at(1), '-1250.50');
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(repository.added.single.initialBalanceCents, -125050);
    });

    testWidgets('never sets the cached balance itself', (tester) async {
      // E-18: current_balance_cents is maintained by the writes that move it.
      // A form that set it directly would put the cache and the history into a
      // disagreement nothing could detect.
      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'Savings');
      await tester.enterText(find.byType(TextField).at(1), '5000');
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(repository.added.single.initialBalanceCents, 500000);
      expect(repository.added.single.currentBalanceCents, 0);
    });

    testWidgets('shows the failure instead of pretending it saved', (
      tester,
    ) async {
      repository.failWith = const CacheFailure('The database is locked.');

      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'Cash');
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(find.text('The database is locked.'), findsOneWidget);
      // Still on the form, because nothing was written.
      expect(find.text('New account'), findsOneWidget);
    });
  });

  group('a currency the app cannot convert', () {
    testWidgets('warns at the moment the choice is made', (tester) async {
      // E-25. The consequence becomes true when the currency is chosen, and
      // finding out later from a total that quietly omits the account is
      // worse than being told here.
      await open(tester);

      expect(find.textContaining('cannot convert'), findsNothing);

      await tester.enterText(find.byType(TextField).last, 'USD');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('left out of your total balance'),
        findsOneWidget,
      );
    });

    testWidgets('stays quiet for the base currency', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField).last, 'LKR');
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot convert'), findsNothing);
    });
  });

  group('editing an account', () {
    testWidgets('opens with the account already filled in', (tester) async {
      await open(tester, initial: existing());

      expect(find.text('Edit account'), findsOneWidget);
      expect(find.text('Commercial Bank'), findsOneWidget);
      // The opening balance, not the cached one — 2,500.00 rather than
      // 8,123.45.
      expect(find.text('2,500.00'), findsOneWidget);
      expect(find.text('Bank account'), findsOneWidget);
    });

    testWidgets('updates rather than adding a second account', (tester) async {
      await open(tester, initial: existing());

      await tester.enterText(find.byType(TextField).first, 'Commercial saver');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(repository.added, isEmpty);
      expect(repository.updated, hasLength(1));
      expect(repository.updated.single.id, 4);
      expect(repository.updated.single.name, 'Commercial saver');
    });

    testWidgets('carries the cached balance through untouched', (tester) async {
      // The form must neither set nor reset it (E-18).
      await open(tester, initial: existing());

      await tester.enterText(find.byType(TextField).first, 'Renamed');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(repository.updated.single.currentBalanceCents, 812345);
    });

    testWidgets('keeps the Include-in-Total choice it was opened with', (
      tester,
    ) async {
      // FR-ACC-002. The fixture has it off; saving without touching it must
      // not quietly turn it back on.
      await open(tester, initial: existing());

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(repository.updated.single.includeInTotal, isFalse);
    });
  });

  group('the icon picker', () {
    testWidgets('offers the catalogue and saves the chosen key', (
      tester,
    ) async {
      // FR-ACC-006, as amended by E-26. The stored value is the key, not the
      // glyph or its position.
      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'Bitcoin stash');
      await tester.tap(find.byTooltip('Cryptocurrency'), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(repository.added.single.icon, 'crypto');
    });

    testWidgets('starts on the seed default for a new account', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField).first, 'Cash');
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(repository.added.single.icon, 'wallet');
    });
  });
}
