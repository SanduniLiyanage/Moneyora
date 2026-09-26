import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/backup_file.dart';
import '../../domain/entities/backup_status.dart';
import '../../domain/entities/restore_summary.dart';
import '../../domain/repositories/backup_repository.dart';
import '../datasources/backup_local_datasource.dart';
import '../datasources/backup_log.dart';

/// Turns the datasource's exceptions into failures. The layer boundary.
class BackupRepositoryImpl implements BackupRepository {
  /// Creates the repository. [clock] names the file and dates the backup;
  /// [log] is the keychain's record of when this phone last saved one.
  BackupRepositoryImpl(
    this._source, {
    required this._log,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final BackupLocalDataSource _source;
  final BackupLog _log;
  final DateTime Function() _clock;

  @override
  Future<Either<Failure, BackupFile>> create(String password) =>
      _guard(() => _source.create(password, now: _clock()));

  @override
  Future<Either<Failure, RestoreSummary>> restore(
    Uint8List bytes,
    String password,
  ) => _guard(() => _source.restore(bytes, password));

  @override
  Future<Either<Failure, Unit>> clearAll() => _guard(() async {
    await _source.clearAll();
    return unit;
  });

  @override
  Future<Either<Failure, BackupFile>> exportTransactionsCsv() =>
      _guard(() => _source.exportCsv(now: _clock()));

  @override
  Future<Either<Failure, BackupStatus>> status(DateTime now) => _guard(
    () async => BackupStatus(
      lastSavedAt: await _log.lastSavedAt(),
      firstSeenAt: await _log.firstSeenAt(now),
      transactionCount: await _source.transactionCount(),
    ),
  );

  @override
  Future<Either<Failure, Unit>> recordSaved(DateTime at) => _guard(() async {
    await _log.recordSaved(at);
    return unit;
  });

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
