import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/backup_file.dart';
import '../../domain/entities/restore_summary.dart';
import '../../domain/repositories/backup_repository.dart';
import '../datasources/backup_local_datasource.dart';

/// Turns the datasource's exceptions into failures. The layer boundary.
class BackupRepositoryImpl implements BackupRepository {
  /// Creates the repository. [clock] names the file and dates the backup.
  BackupRepositoryImpl(this._source, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final BackupLocalDataSource _source;
  final DateTime Function() _clock;

  @override
  Future<Either<Failure, BackupFile>> create(String password) =>
      _guard(() => _source.create(password, now: _clock()));

  @override
  Future<Either<Failure, RestoreSummary>> restore(
    Uint8List bytes,
    String password,
  ) => _guard(() => _source.restore(bytes, password));

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Right(await body());
    } on EncryptionException catch (e) {
      return Left(EncryptionFailure(e.message));
    } on AppException catch (e) {
      return Left(CacheFailure(e.message));
    }
  }
}
