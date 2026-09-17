import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';
import 'conversion_table.dart';

export 'conversion_table.dart';

/// Reads the [ConversionTable], from outside `features/settings/`.
/// FR-ACC-005.
///
/// The accounts feature converts balances with it and the transfer screen
/// pre-fills a credited amount from it; neither may import the settings
/// feature (rule 4 of `check_architecture.sh`). The settings feature's data
/// layer fulfils this, and `injection.dart` hands it out — the same shape as
/// [AccountReader] (E-27).
abstract interface class ConversionReader {
  /// The table, kept live: a new rate or a new base currency reaches every
  /// total on screen without a restart.
  Stream<Either<Failure, ConversionTable>> watch();
}
