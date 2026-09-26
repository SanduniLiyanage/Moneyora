import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/restore_summary.dart';
import '../repositories/backup_repository.dart';

/// Replaces everything the app holds with a backup. FR-BAK-005, FR-SET-009.
///
/// A restore does not merge. Two ledgers with overlapping history merged
/// row by row would double every transaction both of them recorded, and
/// nothing in a row says which copy is the same money. So the backup
/// replaces what is here, all or nothing, and the screen says so before it
/// runs.
class RestoreBackup implements UseCase<RestoreSummary, RestoreRequest> {
  /// Creates the use case.
  const RestoreBackup(this._repository);

  final BackupRepository _repository;

  @override
  Future<Either<Failure, RestoreSummary>> call(RestoreRequest params) async {
    if (params.password.isEmpty) {
      return const Left(
        ValidationFailure(
          'Enter the password the backup was made with.',
          field: 'password',
        ),
      );
    }
    return _repository.restore(params.bytes, params.password);
  }
}

/// The backup to restore, and the password it was made with.
class RestoreRequest extends Equatable {
  /// Creates a request.
  const RestoreRequest({required this.bytes, required this.password});

  /// The `.mora` file's contents.
  final Uint8List bytes;

  /// The password it was sealed under.
  final String password;

  @override
  List<Object?> get props => [bytes, password];
}
