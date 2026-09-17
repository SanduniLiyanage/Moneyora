@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/domain/repositories/account_repository.dart';
import 'package:moneyora/features/settings/domain/entities/exchange_rate.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';
import 'package:moneyora/features/settings/domain/repositories/exchange_rate_repository.dart';
import 'package:moneyora/features/settings/domain/repositories/settings_repository.dart';
import 'package:moneyora/features/settings/presentation/pages/settings_page.dart';
import 'package:moneyora/features/settings/presentation/providers/settings_providers.dart';
import 'package:moneyora/injection.dart';

/// The settings screen, driven the way a person drives it.
///
/// The repositories are fakes; everything above them is real — the widgets,
/// the providers, and the actual `SetTheme` and `RecomputeAllAccountBalances`
/// use cases. What is asserted is that a theme choice is written and then
/// drawn by the `MaterialApp` above the screen, that the E-18 sweep runs
/// when, and only when, the user asks for it and confirms, and that a refusal
/// reaches the screen in the failure's own words.
class _FakeSettingsRepository implements SettingsRepository {
  UserSettings stored = const UserSettings();

  /// Every settings value saved, in order.
  final List<UserSettings> saved = [];

  /// Set to make reads and writes fail, as a locked database would.
  Failure? failWith;

  final _changes = StreamController<void>.broadcast();

  Future<void> dispose() => _changes.close();

  @override
  Future<Either<Failure, UserSettings>> get() async {
    if (failWith case final failure?) return Left(failure);
    return Right(stored);
  }

  @override
  Future<Either<Failure, Unit>> save(UserSettings settings) async {
    if (failWith case final failure?) return Left(failure);
    saved.add(settings);
    stored = settings;
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Stream<Either<Failure, UserSettings>> watch() async* {
    yield await get();
    await for (final _ in _changes.stream) {
      yield await get();
    }
  }
}

class _FakeRatesRepository implements ExchangeRateRepository {
  List<ExchangeRate> stored = const [];

  @override
  Stream<Either<Failure, List<ExchangeRate>>> watch() =>
      Stream.value(Right(stored));

  @override
  Future<Either<Failure, Unit>> set(ExchangeRate rate) async =>
      const Right(unit);

  @override
  Future<Either<Failure, Unit>> remove({
    required String fromCurrency,
    required String toCurrency,
  }) async => const Right(unit);
}

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
  late _FakeSettingsRepository settings;
  late _FakeRatesRepository rates;

  setUp(() {
    repository = _FakeRepository();
    settings = _FakeSettingsRepository();
    rates = _FakeRatesRepository();
  });

  tearDown(() => settings.dispose());

  /// The page under a `MaterialApp` themed the way `MoneyoraApp` themes it,
  /// so the theme test can assert on what is actually drawn.
  Widget boot() => ProviderScope(
    overrides: [
      accountRepositoryProvider.overrideWith((ref) async => repository),
      settingsRepositoryProvider.overrideWith((ref) async => settings),
      exchangeRateRepositoryProvider.overrideWith((ref) async => rates),
    ],
    child: Consumer(
      builder: (context, ref, _) => MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ref.watch(themeModeProvider),
        home: const SettingsPage(),
      ),
    ),
  );

  /// Pumps the page with the whole of it on screen.
  ///
  /// The default 800x600 is shorter than the settings list now, and a
  /// `ListView` builds lazily — the Data section below the fold would not
  /// exist to be tapped.
  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester) async {
    await tester.tap(find.text('Recalculate account balances'));
    await tester.pumpAndSettle();
  }

  Brightness drawnBrightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(SettingsPage))).brightness;

  group('the theme choice', () {
    testWidgets('shows the stored choice', (tester) async {
      settings.stored = const UserSettings(theme: AppThemeMode.dark);
      await open(tester);

      final button = tester.widget<SegmentedButton<AppThemeMode>>(
        find.byType(SegmentedButton<AppThemeMode>),
      );
      expect(button.selected, {AppThemeMode.dark});
    });

    testWidgets('writes the choice and the app is drawn in it', (tester) async {
      await open(tester);
      expect(drawnBrightness(tester), Brightness.light);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      // One write, of the whole row with only the theme changed.
      expect(settings.saved, [const UserSettings(theme: AppThemeMode.dark)]);
      // And the MaterialApp above the page followed it, without the page
      // touching a theme itself.
      expect(drawnBrightness(tester), Brightness.dark);
    });

    testWidgets('shows the failure in its own words', (tester) async {
      await open(tester);
      settings.failWith = const CacheFailure('database is locked');

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(find.text('database is locked'), findsOneWidget);
      expect(settings.saved, isEmpty);
    });

    testWidgets('offers no choice while the row cannot be read', (
      tester,
    ) async {
      // The subtitle carries the sentence; the buttons are absent rather than
      // greyed, because there is no stored value for them to be changing.
      settings.failWith = const CacheFailure(
        'The settings row has not been seeded.',
      );
      await open(tester);

      expect(find.byType(SegmentedButton<AppThemeMode>), findsNothing);
      expect(
        find.text('The settings row has not been seeded.'),
        findsOneWidget,
      );
    });
  });

  group('the base currency', () {
    testWidgets('shows the stored code', (tester) async {
      settings.stored = const UserSettings(currency: 'USD');
      await open(tester);

      expect(find.textContaining('USD — the currency'), findsOneWidget);
    });

    testWidgets('writes a new code, normalised', (tester) async {
      await open(tester);

      await tester.tap(find.text('Base currency'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'usd');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(settings.saved, [const UserSettings(currency: 'USD')]);
      expect(find.textContaining('USD — the currency'), findsOneWidget);
    });

    testWidgets('refuses a bad code in the use case\'s words, and writes '
        'nothing', (tester) async {
      await open(tester);

      await tester.tap(find.text('Base currency'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Rs');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a three-letter currency code, like LKR.'),
        findsOneWidget,
      );
      expect(settings.saved, isEmpty);
    });

    testWidgets('cancelling writes nothing', (tester) async {
      await open(tester);

      await tester.tap(find.text('Base currency'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'USD');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(settings.saved, isEmpty);
    });
  });

  group('the exchange-rates row', () {
    testWidgets('says how many rates there are', (tester) async {
      await open(tester);
      expect(find.textContaining('None yet.'), findsOneWidget);
    });

    testWidgets('counts them', (tester) async {
      rates.stored = [
        ExchangeRate(
          fromCurrency: 'USD',
          toCurrency: 'LKR',
          rateMicros: 300000000,
          updatedAt: DateTime(2026),
        ),
        ExchangeRate(
          fromCurrency: 'EUR',
          toCurrency: 'LKR',
          rateMicros: 330000000,
          updatedAt: DateTime(2026),
        ),
      ];
      await open(tester);
      expect(find.text('2 rates.'), findsOneWidget);
    });
  });

  group('the calendar', () {
    testWidgets('shows the stored week start and writes a new one', (
      tester,
    ) async {
      await open(tester);

      final button = tester.widget<SegmentedButton<int>>(
        find.byType(SegmentedButton<int>),
      );
      // The seeded default is Sunday (FR-SET-004, DBD §3.1).
      expect(button.selected, {DateTime.sunday});

      await tester.tap(find.text('Monday'));
      await tester.pumpAndSettle();

      expect(settings.saved, [
        const UserSettings(firstDayOfWeek: DateTime.monday),
      ]);
    });

    testWidgets('writes the first day of the month, and says what it means', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Day 1 — the calendar month.'), findsOneWidget);

      await tester.tap(find.text('Month starts on day'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '25');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(settings.saved, [const UserSettings(firstDayOfMonth: 25)]);
      expect(
        find.textContaining('Day 25 — a month runs from the 25th'),
        findsOneWidget,
      );
    });

    testWidgets('refuses a day every month does not have, in the use '
        'case\'s words', (tester) async {
      await open(tester);

      await tester.tap(find.text('Month starts on day'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '31');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose a day from 1 to 28, so every month has it.'),
        findsOneWidget,
      );
      expect(settings.saved, isEmpty);
    });

    testWidgets('writes the lookback within 1–24 and refuses outside', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('6 months of spending.'), findsOneWidget);

      await tester.tap(find.text('Money Plan looks back'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '25');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Choose between 1 and 24 months.'), findsOneWidget);
      expect(settings.saved, isEmpty);

      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(settings.saved, [const UserSettings(planAnalysisMonths: 12)]);
      expect(find.text('12 months of spending.'), findsOneWidget);
    });
  });

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
