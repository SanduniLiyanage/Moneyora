import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/local_notifier.dart';
import 'package:moneyora/features/backup/domain/entities/backup_file.dart';
import 'package:moneyora/features/backup/domain/entities/backup_status.dart';
import 'package:moneyora/features/backup/domain/entities/restore_summary.dart';
import 'package:moneyora/features/backup/domain/repositories/backup_repository.dart';
import 'package:moneyora/features/backup/domain/usecases/schedule_backup_reminder.dart';

/// FR-BAK-006 on exact days, with the clock handed in.
void main() {
  late _FakeStatus backups;
  late _FakeNotifier notifier;
  late ScheduleBackupReminder schedule;

  // A Saturday afternoon.
  final now = DateTime(2026, 9, 26, 15, 30);

  setUp(() {
    backups = _FakeStatus();
    notifier = _FakeNotifier();
    schedule = ScheduleBackupReminder(backups, notifier);
  });

  group('dueAt', () {
    test('a week after the last backup, when that is still ahead', () {
      expect(
        ScheduleBackupReminder.dueAt(DateTime(2026, 9, 22, 20), now),
        DateTime(2026, 9, 29, 20),
      );
    });

    test('overdue after 9:00 comes the next morning at 9:00', () {
      expect(
        ScheduleBackupReminder.dueAt(DateTime(2026, 9, 1), now),
        DateTime(2026, 9, 27, 9),
      );
    });

    test('overdue before 9:00 comes this morning at 9:00', () {
      expect(
        ScheduleBackupReminder.dueAt(
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 26, 7),
        ),
        DateTime(2026, 9, 26, 9),
      );
    });

    test('exactly a week is due now, so the next 9:00', () {
      expect(
        ScheduleBackupReminder.dueAt(
          now.subtract(const Duration(days: 7)),
          now,
        ),
        DateTime(2026, 9, 27, 9),
      );
    });
  });

  test('with nothing to lose, withdraws the reminder', () async {
    backups.current = BackupStatus(
      lastSavedAt: null,
      firstSeenAt: DateTime(2026, 1, 1),
      transactionCount: 0,
    );

    expect(await schedule(now), const Right<Failure, Unit>(unit));

    expect(notifier.cancelled, [AppNotification.backupReminderId]);
    expect(notifier.scheduled, isEmpty);
  });

  test('never backed up counts from the first check, and says so', () async {
    backups.current = BackupStatus(
      lastSavedAt: null,
      firstSeenAt: DateTime(2026, 9, 25, 10),
      transactionCount: 12,
    );

    await schedule(now);

    final (notification, at) = notifier.scheduled.single;
    expect(at, DateTime(2026, 10, 2, 10));
    expect(notification.id, AppNotification.backupReminderId);
    expect(notification.kind, NotificationKind.backupReminder);
    expect(notification.payload, ScheduleBackupReminder.payload);
    expect(notification.body, startsWith('Nothing on this phone'));
  });

  test('backed up before counts from that backup', () async {
    backups.current = BackupStatus(
      lastSavedAt: DateTime(2026, 9, 24, 8),
      firstSeenAt: DateTime(2026, 1, 1),
      transactionCount: 12,
    );

    await schedule(now);

    final (notification, at) = notifier.scheduled.single;
    expect(at, DateTime(2026, 10, 1, 8));
    expect(notification.body, startsWith('Your last backup'));
  });

  test(
    'passes a failure to read the status on, and schedules nothing',
    () async {
      backups.fail = const CacheFailure('locked');

      expect(
        await schedule(now),
        const Left<Failure, Unit>(CacheFailure('locked')),
      );
      expect(notifier.scheduled, isEmpty);
    },
  );
}

class _FakeStatus implements BackupRepository {
  BackupStatus? current;
  Failure? fail;

  @override
  Future<Either<Failure, BackupStatus>> status(DateTime now) async =>
      fail != null ? Left(fail!) : Right(current!);

  @override
  Future<Either<Failure, Unit>> recordSaved(DateTime at) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, BackupFile>> create(String password) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, RestoreSummary>> restore(
    Uint8List bytes,
    String password,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> clearAll() => throw UnimplementedError();

  @override
  Future<Either<Failure, BackupFile>> exportTransactionsCsv() =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, BackupFile>> exportTransactionsPdf() =>
      throw UnimplementedError();
}

class _FakeNotifier implements LocalNotifier {
  final List<(AppNotification, DateTime)> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<Either<Failure, Unit>> schedule(
    AppNotification notification,
    DateTime at,
  ) async {
    scheduled.add((notification, at));
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> cancel(int id) async {
    cancelled.add(id);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, bool>> requestPermission() =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> show(AppNotification notification) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Set<int>>> scheduledIds() =>
      throw UnimplementedError();
}
