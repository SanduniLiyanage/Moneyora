import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/backup_repository.dart';

/// Notes that a backup was saved at the given moment. FR-BAK-006.
///
/// Saved, not made: a backup sealed and then abandoned in the save dialog
/// protects nothing, so it does not put the reminder off.
class RecordBackupSaved implements UseCase<Unit, DateTime> {
  /// Creates the use case.
  const RecordBackupSaved(this._repository);

  final BackupRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(DateTime params) =>
      _repository.recordSaved(params);
}
