/// The settings feature's answer to [ConversionReader]: the base currency
/// from the `users` row and every rate from `exchange_rates`, joined into
/// one live value.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/conversion_reader.dart';
import '../../../../core/ports/exchange_rate.dart';
import '../../domain/repositories/exchange_rate_repository.dart';
import '../../domain/repositories/settings_repository.dart';

/// Fulfils [ConversionReader] over the two settings repositories.
///
/// A repository-of-repositories rather than a third datasource, because
/// nothing here is new SQL: it is the base currency and the rate list the
/// feature already reads, emitted together so a consumer never sees one
/// without the other. Either stream failing fails the table — a total
/// computed against half the picture would be wrong in a way that looks
/// right.
class ConversionReaderImpl implements ConversionReader {
  /// Creates the reader.
  const ConversionReaderImpl(this._settings, this._rates);

  final SettingsRepository _settings;
  final ExchangeRateRepository _rates;

  @override
  Stream<Either<Failure, ConversionTable>> watch() {
    late final StreamController<Either<Failure, ConversionTable>> controller;
    StreamSubscription<Either<Failure, String>>? base;
    StreamSubscription<Either<Failure, List<ExchangeRate>>>? rates;
    Either<Failure, String>? latestBase;
    Either<Failure, List<ExchangeRate>>? latestRates;

    void emit() {
      final b = latestBase;
      final r = latestRates;
      // Wait for both: the first frame after listening should be the whole
      // table, not a base with no rates followed by a correction.
      if (b == null || r == null || controller.isClosed) return;
      controller.add(
        b.flatMap(
          (currency) => r.map(
            (list) => ConversionTable(baseCurrency: currency, rates: list),
          ),
        ),
      );
    }

    controller = StreamController<Either<Failure, ConversionTable>>(
      onListen: () {
        base = _settings.watch().map((r) => r.map((s) => s.currency)).listen((
          value,
        ) {
          latestBase = value;
          emit();
        });
        rates = _rates.watch().listen((value) {
          latestRates = value;
          emit();
        });
      },
      onCancel: () async {
        await base?.cancel();
        await rates?.cancel();
        await controller.close();
      },
    );

    return controller.stream;
  }
}
