import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/backup_file.dart';
import '../entities/backup_status.dart';
import '../entities/restore_summary.dart';

/// Makes a backup of everything the app holds, and restores one.
/// FR-BAK-001, FR-BAK-005, FR-SET-009.
abstract class BackupRepository {
  /// Seals every row and every kept receipt photo under [password] as a
  /// `.mora` file (E-08).
  Future<Either<Failure, BackupFile>> create(String password);

  /// Replaces everything the app holds with the backup [bytes], opened with
  /// [password]. All or nothing: a backup that will not open, or fails
  /// partway, leaves the ledger as it was.
  Future<Either<Failure, RestoreSummary>> restore(
    Uint8List bytes,
    String password,
  );

  /// Deletes everything and writes the first-launch defaults back.
  /// FR-SET-009.
  Future<Either<Failure, Unit>> clearAll();

  /// Every transaction as a CSV file. FR-RPT-007.
  Future<Either<Failure, BackupFile>> exportTransactionsCsv();

  /// Where this phone stands on backups, as of [now]. FR-BAK-006.
  Future<Either<Failure, BackupStatus>> status(DateTime now);

  /// Records that a backup was saved at [at]. FR-BAK-006.
  Future<Either<Failure, Unit>> recordSaved(DateTime at);
}
