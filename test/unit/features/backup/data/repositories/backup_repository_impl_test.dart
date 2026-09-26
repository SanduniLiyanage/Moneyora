import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/backup/data/datasources/backup_local_datasource.dart';
import 'package:moneyora/features/backup/data/repositories/backup_repository_impl.dart';
import 'package:moneyora/features/backup/domain/entities/backup_file.dart';
import 'package:moneyora/features/backup/domain/entities/restore_summary.dart';

void main() {
  late _FakeSource source;
  late BackupRepositoryImpl repository;
  final now = DateTime.utc(2026, 9, 27, 8);

  setUp(() {
    source = _FakeSource();
    repository = BackupRepositoryImpl(source, clock: () => now);
  });

  test('dates the backup by its clock', () async {
    expect(
      await repository.create('password'),
      Right<Failure, BackupFile>(_file),
    );
    expect(source.createdAt, now);
  });

  test('a password that does not open it is an encryption failure', () async {
    source.throwWith = const EncryptionException(
      'That password does not open this backup.',
    );

    expect(
      await repository.restore(_bytes, 'x'),
      const Left<Failure, RestoreSummary>(
        EncryptionFailure('That password does not open this backup.'),
      ),
    );
  });

  test("anything else is a cache failure, in the datasource's words", () async {
    source.throwWith = const CacheException(
      'That file is not a Moneyora backup.',
    );

    expect(
      await repository.restore(_bytes, 'x'),
      const Left<Failure, RestoreSummary>(
        CacheFailure('That file is not a Moneyora backup.'),
      ),
    );
    expect(
      await repository.create('password'),
      const Left<Failure, BackupFile>(
        CacheFailure('That file is not a Moneyora backup.'),
      ),
    );
  });
}

class _FakeSource implements BackupLocalDataSource {
  AppException? throwWith;
  DateTime? createdAt;

  @override
  Future<BackupFile> create(String password, {required DateTime now}) async {
    if (throwWith case final e?) throw e;
    createdAt = now;
    return _file;
  }

  @override
  Future<RestoreSummary> restore(Uint8List bytes, String password) async {
    if (throwWith case final e?) throw e;
    return RestoreSummary(
      backedUpAt: DateTime.utc(2026),
      transactionCount: 0,
      photoCount: 0,
    );
  }
}

final _bytes = Uint8List.fromList([1, 2, 3]);
final _file = BackupFile(name: 'moneyora-2026-09-27.mora', bytes: _bytes);
