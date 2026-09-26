import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/backup_file.dart';
import '../repositories/backup_repository.dart';

/// Every transaction as a CSV file a spreadsheet opens. FR-RPT-007.
///
/// One row per transaction, oldest first: date, type, signed amount in the
/// account's own currency, currency, account, category, note. A split
/// expense is one row under its dominant category (E-04), the way the list
/// shows it; a transfer is its two halves, out and in. Unlike a backup it
/// is not encrypted — it is for reading elsewhere, and the screen says so.
class ExportTransactionsCsv implements UseCase<BackupFile, NoParams> {
  /// Creates the use case.
  const ExportTransactionsCsv(this._repository);

  final BackupRepository _repository;

  @override
  Future<Either<Failure, BackupFile>> call(NoParams params) =>
      _repository.exportTransactionsCsv();
}
