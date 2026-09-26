import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/backup_file.dart';
import '../repositories/backup_repository.dart';

/// Makes an encrypted backup a person can take to another phone.
/// FR-BAK-001, FR-SET-009, NFR-PRT-004.
///
/// The password is the backup's only key (E-38): nothing on this phone can
/// open the file without it, and nothing can recover it. So it has a
/// minimum length, and the screen asks for it twice.
class CreateBackup implements UseCase<BackupFile, String> {
  /// Creates the use case.
  const CreateBackup(this._repository);

  final BackupRepository _repository;

  /// The shortest password accepted.
  static const int minPasswordLength = 8;

  @override
  Future<Either<Failure, BackupFile>> call(String params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);
    return _repository.create(params);
  }

  /// Returns the reason [password] is refused, or null if it is fine.
  static ValidationFailure? validate(String password) {
    if (password.length < minPasswordLength) {
      return const ValidationFailure(
        'Use at least 8 characters. This password is the only way to open '
        'the backup.',
        field: 'password',
      );
    }
    return null;
  }
}
