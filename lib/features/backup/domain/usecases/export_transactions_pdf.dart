import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/backup_file.dart';
import '../repositories/backup_repository.dart';

/// Every transaction as a printable PDF. FR-RPT-007.
///
/// The same rows as the CSV, laid out on A4 with a total per currency —
/// never one across currencies, which would convert at whatever rate the
/// user holds today (E-34). For printing and sharing, not for another
/// program to read; the CSV is that.
class ExportTransactionsPdf implements UseCase<BackupFile, NoParams> {
  /// Creates the use case.
  const ExportTransactionsPdf(this._repository);

  final BackupRepository _repository;

  @override
  Future<Either<Failure, BackupFile>> call(NoParams params) =>
      _repository.exportTransactionsPdf();
}
