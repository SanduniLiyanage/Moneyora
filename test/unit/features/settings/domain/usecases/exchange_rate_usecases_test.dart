import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/usecases/usecase.dart';
import 'package:moneyora/features/settings/domain/entities/exchange_rate.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';
import 'package:moneyora/features/settings/domain/repositories/exchange_rate_repository.dart';
import 'package:moneyora/features/settings/domain/repositories/settings_repository.dart';
import 'package:moneyora/features/settings/domain/usecases/remove_exchange_rate.dart';
import 'package:moneyora/features/settings/domain/usecases/set_base_currency.dart';
import 'package:moneyora/features/settings/domain/usecases/set_exchange_rate.dart';
import 'package:moneyora/features/settings/domain/usecases/watch_exchange_rates.dart';

/// The rate use cases and the base-currency setting, one fake each.
void main() {
  late _FakeRates rates;
  late _FakeSettings settings;

  final when = DateTime(2026, 9, 17);

  ExchangeRate rate({
    String from = 'USD',
    String to = 'LKR',
    int micros = 300000000,
  }) => ExchangeRate(
    fromCurrency: from,
    toCurrency: to,
    rateMicros: micros,
    updatedAt: when,
  );

  setUp(() {
    rates = _FakeRates();
    settings = _FakeSettings();
  });

  group('SetExchangeRate', () {
    test('stores the rate with its codes normalised', () async {
      final result = await SetExchangeRate(rates)(
        rate(from: ' usd ', to: 'lkr'),
      );

      expect(result, const Right<Failure, Unit>(unit));
      expect(rates.stored, [rate()]);
    });

    test('refuses a code that is not three letters', () {
      expect(SetExchangeRate.validate(rate(from: 'US'))?.field, 'fromCurrency');
      expect(SetExchangeRate.validate(rate(to: 'LKRS'))?.field, 'toCurrency');
      expect(SetExchangeRate.validate(rate(to: '12A'))?.field, 'toCurrency');
    });

    test('refuses a currency against itself', () async {
      final result = await SetExchangeRate(rates)(rate(from: 'LKR', to: 'lkr'));

      expect(
        result,
        const Left<Failure, Unit>(
          ValidationFailure(
            'Choose two different currencies — a currency is always worth '
            'itself.',
            field: 'toCurrency',
          ),
        ),
      );
      expect(rates.stored, isEmpty);
    });

    test('refuses a rate of nothing', () {
      expect(SetExchangeRate.validate(rate(micros: 0))?.field, 'rate');
      expect(SetExchangeRate.validate(rate(micros: -1))?.field, 'rate');
    });

    test('surfaces a failed write', () async {
      rates.failWith = const CacheFailure('database is locked');

      final result = await SetExchangeRate(rates)(rate());

      expect(
        result,
        const Left<Failure, Unit>(CacheFailure('database is locked')),
      );
    });
  });

  group('RemoveExchangeRate', () {
    test('forgets the pair, codes normalised', () async {
      final result = await RemoveExchangeRate(rates)(
        const CurrencyPair(fromCurrency: 'usd', toCurrency: ' lkr'),
      );

      expect(result, const Right<Failure, Unit>(unit));
      expect(rates.removed, [('USD', 'LKR')]);
    });
  });

  group('WatchExchangeRates', () {
    test('forwards what the repository emits', () async {
      rates.stored.add(rate());

      final first = await WatchExchangeRates(rates)(const NoParams()).first;

      expect(first.toNullable(), [rate()]);
    });
  });

  group('SetBaseCurrency', () {
    test('changes the currency and nothing else', () async {
      settings.stored = const UserSettings(theme: AppThemeMode.dark);

      final result = await SetBaseCurrency(settings)(' usd ');

      expect(result, const Right<Failure, Unit>(unit));
      expect(
        settings.saved,
        const UserSettings(theme: AppThemeMode.dark, currency: 'USD'),
      );
    });

    test(
      'refuses a code that is not three letters, and writes nothing',
      () async {
        final result = await SetBaseCurrency(settings)('Rs');

        expect(
          result,
          const Left<Failure, Unit>(
            ValidationFailure(
              'Enter a three-letter currency code, like LKR.',
              field: 'currency',
            ),
          ),
        );
        expect(settings.saved, isNull);
      },
    );

    test('writes nothing when the row cannot be read', () async {
      settings.failGetWith = const CacheFailure('database is locked');

      final result = await SetBaseCurrency(settings)('USD');

      expect(result.isLeft(), isTrue);
      expect(settings.saved, isNull);
    });
  });
}

class _FakeRates implements ExchangeRateRepository {
  final List<ExchangeRate> stored = [];
  final List<(String, String)> removed = [];
  Failure? failWith;

  @override
  Stream<Either<Failure, List<ExchangeRate>>> watch() =>
      Stream.value(Right(List.of(stored)));

  @override
  Future<Either<Failure, Unit>> set(ExchangeRate rate) async {
    if (failWith case final failure?) return Left(failure);
    stored.add(rate);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> remove({
    required String fromCurrency,
    required String toCurrency,
  }) async {
    if (failWith case final failure?) return Left(failure);
    removed.add((fromCurrency, toCurrency));
    return const Right(unit);
  }
}

class _FakeSettings implements SettingsRepository {
  UserSettings stored = const UserSettings();
  UserSettings? saved;
  Failure? failGetWith;

  @override
  Future<Either<Failure, UserSettings>> get() async {
    if (failGetWith case final failure?) return Left(failure);
    return Right(stored);
  }

  @override
  Future<Either<Failure, Unit>> save(UserSettings settings) async {
    saved = settings;
    stored = settings;
    return const Right(unit);
  }

  @override
  Stream<Either<Failure, UserSettings>> watch() => Stream.value(Right(stored));
}
