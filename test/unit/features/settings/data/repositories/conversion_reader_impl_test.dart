import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/conversion_table.dart';
import 'package:moneyora/features/settings/data/repositories/conversion_reader_impl.dart';
import 'package:moneyora/features/settings/domain/entities/exchange_rate.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';
import 'package:moneyora/features/settings/domain/repositories/exchange_rate_repository.dart';
import 'package:moneyora/features/settings/domain/repositories/settings_repository.dart';

/// The join: one table from two streams, emitted only once both have spoken,
/// re-emitted when either moves, and failed when either fails.
void main() {
  late _FakeSettings settings;
  late _FakeRates rates;
  late ConversionReaderImpl reader;

  final when = DateTime(2026, 9, 17);
  final usd = ExchangeRate(
    fromCurrency: 'USD',
    toCurrency: 'LKR',
    rateMicros: 300000000,
    updatedAt: when,
  );

  Future<void> settle() async {
    for (var turn = 0; turn < 5; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    settings = _FakeSettings();
    rates = _FakeRates();
    reader = ConversionReaderImpl(settings, rates);
  });

  tearDown(() async {
    await settings.dispose();
    await rates.dispose();
  });

  test('waits for both halves, then emits the whole table', () async {
    final seen = <Either<Failure, ConversionTable>>[];
    final sub = reader.watch().listen(seen.add);
    addTearDown(sub.cancel);

    settings.emit(const Right(UserSettings(currency: 'LKR')));
    await settle();
    expect(seen, isEmpty, reason: 'no rates yet');

    rates.emit(Right([usd]));
    await settle();

    expect(
      seen.single.toNullable(),
      ConversionTable(baseCurrency: 'LKR', rates: [usd]),
    );
  });

  test('follows a base-currency change and a rate change', () async {
    final seen = <Either<Failure, ConversionTable>>[];
    final sub = reader.watch().listen(seen.add);
    addTearDown(sub.cancel);

    settings.emit(const Right(UserSettings(currency: 'LKR')));
    rates.emit(const Right([]));
    await settle();
    settings.emit(const Right(UserSettings(currency: 'USD')));
    await settle();
    rates.emit(Right([usd]));
    await settle();

    expect(seen.map((e) => e.toNullable()!.baseCurrency), [
      'LKR',
      'USD',
      'USD',
    ]);
    expect(seen.last.toNullable()!.rates, [usd]);
  });

  test('either half failing fails the table', () async {
    final seen = <Either<Failure, ConversionTable>>[];
    final sub = reader.watch().listen(seen.add);
    addTearDown(sub.cancel);

    settings.emit(const Left(CacheFailure('locked')));
    rates.emit(const Right([]));
    await settle();

    expect(
      seen.single,
      const Left<Failure, ConversionTable>(CacheFailure('locked')),
    );
  });

  test('cancelling unsubscribes from both', () async {
    final sub = reader.watch().listen((_) {});
    await settle();
    expect(settings.listened, isTrue);
    expect(rates.listened, isTrue);

    await sub.cancel();
    await settle();

    expect(settings.listened, isFalse);
    expect(rates.listened, isFalse);
  });
}

class _FakeSettings implements SettingsRepository {
  final _controller =
      StreamController<Either<Failure, UserSettings>>.broadcast();
  bool get listened => _controller.hasListener;
  void emit(Either<Failure, UserSettings> value) => _controller.add(value);
  Future<void> dispose() => _controller.close();

  @override
  Stream<Either<Failure, UserSettings>> watch() => _controller.stream;

  @override
  Future<Either<Failure, UserSettings>> get() async =>
      const Right(UserSettings());

  @override
  Future<Either<Failure, Unit>> save(UserSettings settings) async =>
      const Right(unit);
}

class _FakeRates implements ExchangeRateRepository {
  final _controller =
      StreamController<Either<Failure, List<ExchangeRate>>>.broadcast();
  bool get listened => _controller.hasListener;
  void emit(Either<Failure, List<ExchangeRate>> value) =>
      _controller.add(value);
  Future<void> dispose() => _controller.close();

  @override
  Stream<Either<Failure, List<ExchangeRate>>> watch() => _controller.stream;

  @override
  Future<Either<Failure, Unit>> set(ExchangeRate rate) async =>
      const Right(unit);

  @override
  Future<Either<Failure, Unit>> remove({
    required String fromCurrency,
    required String toCurrency,
  }) async => const Right(unit);
}
