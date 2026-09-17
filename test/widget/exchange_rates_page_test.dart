@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/settings/domain/entities/exchange_rate.dart';
import 'package:moneyora/features/settings/domain/repositories/exchange_rate_repository.dart';
import 'package:moneyora/features/settings/presentation/pages/exchange_rates_page.dart';
import 'package:moneyora/injection.dart';

/// The rates screen, driven the way a person drives it.
///
/// The repository is a fake with a live stream; everything above it is real,
/// including `SetExchangeRate`'s validation — so the refusals asserted here
/// are the use case's own sentences, not the screen's.
class _FakeRepository implements ExchangeRateRepository {
  final List<ExchangeRate> stored = [];
  final List<(String, String)> removed = [];
  Failure? failWith;

  final _changes = StreamController<void>.broadcast();

  Future<void> dispose() => _changes.close();

  @override
  Stream<Either<Failure, List<ExchangeRate>>> watch() async* {
    yield Right(List.of(stored));
    await for (final _ in _changes.stream) {
      yield Right(List.of(stored));
    }
  }

  @override
  Future<Either<Failure, Unit>> set(ExchangeRate rate) async {
    if (failWith case final failure?) return Left(failure);
    stored
      ..removeWhere(
        (r) =>
            r.fromCurrency == rate.fromCurrency &&
            r.toCurrency == rate.toCurrency,
      )
      ..add(rate);
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> remove({
    required String fromCurrency,
    required String toCurrency,
  }) async {
    if (failWith case final failure?) return Left(failure);
    removed.add((fromCurrency, toCurrency));
    stored.removeWhere(
      (r) => r.fromCurrency == fromCurrency && r.toCurrency == toCurrency,
    );
    _changes.add(null);
    return const Right(unit);
  }
}

void main() {
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());
  tearDown(() => repository.dispose());

  ExchangeRate usd({int micros = 300250000}) => ExchangeRate(
    fromCurrency: 'USD',
    toCurrency: 'LKR',
    rateMicros: micros,
    updatedAt: DateTime(2026, 9, 17),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exchangeRateRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ExchangeRatesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String label, String text) async {
    await tester.enterText(find.widgetWithText(TextField, label), text);
  }

  group('the list', () {
    testWidgets('tells a first-time user what will appear here', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('No exchange rates yet'), findsOneWidget);
    });

    testWidgets('shows each rate as a sentence', (tester) async {
      repository.stored.add(usd());
      await open(tester);

      expect(find.text('USD → LKR'), findsOneWidget);
      expect(find.text('1 USD = 300.25 LKR'), findsOneWidget);
    });
  });

  group('adding', () {
    testWidgets('stores what was typed, codes normalised', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Add rate'));
      await tester.pumpAndSettle();
      await fill(tester, 'From', 'usd');
      await fill(tester, 'To', 'lkr');
      await fill(tester, 'Rate', '300.25');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repository.stored.single.fromCurrency, 'USD');
      expect(repository.stored.single.toCurrency, 'LKR');
      expect(repository.stored.single.rateMicros, 300250000);
      expect(find.text('1 USD = 300.25 LKR'), findsOneWidget);
    });

    testWidgets('refuses a currency against itself, in the use case\'s '
        'words', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Add rate'));
      await tester.pumpAndSettle();
      await fill(tester, 'From', 'LKR');
      await fill(tester, 'To', 'LKR');
      await fill(tester, 'Rate', '1');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Choose two different currencies — a currency is always worth '
          'itself.',
        ),
        findsOneWidget,
      );
      expect(repository.stored, isEmpty);
    });

    testWidgets('refuses a rate of nothing next to the rate field', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.byTooltip('Add rate'));
      await tester.pumpAndSettle();
      await fill(tester, 'From', 'USD');
      await fill(tester, 'To', 'LKR');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a rate greater than zero.'), findsOneWidget);
      expect(repository.stored, isEmpty);
    });

    testWidgets('shows a write failure instead of pretending', (tester) async {
      repository.failWith = const CacheFailure('database is locked');
      await open(tester);

      await tester.tap(find.byTooltip('Add rate'));
      await tester.pumpAndSettle();
      await fill(tester, 'From', 'USD');
      await fill(tester, 'To', 'LKR');
      await fill(tester, 'Rate', '300');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('database is locked'), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('changes the number and keeps the pair', (tester) async {
      repository.stored.add(usd());
      await open(tester);

      await tester.tap(find.text('USD → LKR'));
      await tester.pumpAndSettle();
      // The pair is the row's identity, so only the rate is editable.
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'From'))
            .enabled,
        isFalse,
      );
      await fill(tester, 'Rate', '301');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repository.stored.single.rateMicros, 301000000);
      expect(find.text('1 USD = 301 LKR'), findsOneWidget);
    });
  });

  group('removing', () {
    testWidgets('asks first, and cancelling keeps the rate', (tester) async {
      repository.stored.add(usd());
      await open(tester);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove USD → LKR?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.removed, isEmpty);
      expect(find.text('USD → LKR'), findsOneWidget);
    });

    testWidgets('forgets the pair once confirmed', (tester) async {
      repository.stored.add(usd());
      await open(tester);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(repository.removed, [('USD', 'LKR')]);
      expect(find.text('No exchange rates yet'), findsOneWidget);
    });
  });
}
