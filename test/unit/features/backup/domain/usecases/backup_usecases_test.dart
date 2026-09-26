import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/backup/domain/entities/backup_file.dart';
import 'package:moneyora/features/backup/domain/entities/restore_summary.dart';
import 'package:moneyora/features/backup/domain/repositories/backup_repository.dart';
import 'package:moneyora/features/backup/domain/usecases/create_backup.dart';
import 'package:moneyora/features/backup/domain/usecases/restore_backup.dart';

void main() {
  late _FakeBackups backups;

  setUp(() => backups = _FakeBackups());

  group('CreateBackup', () {
    test('seals under a password of eight characters or more', () async {
      expect(
        await CreateBackup(backups)('12345678'),
        Right<Failure, BackupFile>(_file),
      );
      expect(backups.createdWith, '12345678');
    });

    test('refuses a shorter one, saying why it matters', () async {
      final result = await CreateBackup(backups)('1234567');

      expect(
        result,
        const Left<Failure, BackupFile>(
          ValidationFailure(
            'Use at least 8 characters. This password is the only way to '
            'open the backup.',
            field: 'password',
          ),
        ),
      );
      expect(backups.createdWith, isNull);
    });
  });

  group('RestoreBackup', () {
    test('hands the file and password on', () async {
      final result = await RestoreBackup(backups)(
        RestoreRequest(bytes: _bytes, password: 'pw'),
      );

      expect(result.isRight(), isTrue);
      expect(backups.restored, (_bytes, 'pw'));
    });

    test('asks for the password before trying the file', () async {
      final result = await RestoreBackup(backups)(
        RestoreRequest(bytes: _bytes, password: ''),
      );

      expect(
        result,
        const Left<Failure, RestoreSummary>(
          ValidationFailure(
            'Enter the password the backup was made with.',
            field: 'password',
          ),
        ),
      );
      expect(backups.restored, isNull);
    });
  });
}

class _FakeBackups implements BackupRepository {
  int cleared = 0;
  String? createdWith;
  (Uint8List, String)? restored;

  @override
  Future<Either<Failure, BackupFile>> create(String password) async {
    createdWith = password;
    return Right(_file);
  }

  @override
  Future<Either<Failure, RestoreSummary>> restore(
    Uint8List bytes,
    String password,
  ) async {
    restored = (bytes, password);
    return Right(
      RestoreSummary(
        backedUpAt: DateTime.utc(2026, 9, 27),
        transactionCount: 0,
        photoCount: 0,
      ),
    );
  }

  @override
  Future<Either<Failure, Unit>> clearAll() async {
    cleared++;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, BackupFile>> exportTransactionsCsv() async =>
      Right(_csv);
}

final _bytes = Uint8List.fromList([1, 2, 3]);
final _file = BackupFile(name: 'moneyora-2026-09-27.mora', bytes: _bytes);

final _csv = BackupFile(
  name: 'moneyora-transactions-2026-09-27.csv',
  bytes: Uint8List.fromList([4, 5]),
);
