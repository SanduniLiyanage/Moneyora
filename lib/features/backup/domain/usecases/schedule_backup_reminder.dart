import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/local_notifier.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/backup_repository.dart';

/// Keeps one reminder pending for the day a week passes without a backup.
/// FR-BAK-006.
///
/// Run on launch, after any change to the data, and after a backup is
/// saved. It schedules rather than checks, so the reminder arrives whether
/// or not the app is opened that day:
///
/// * **due** seven days after the last saved backup — or, if there has
///   never been one, after the day the app first checked;
/// * **overdue**, it comes at the next 9:00, so a phone that is never
///   backed up hears about it once a morning, not once a launch;
/// * **nothing to lose**, no transactions yet, and it is withdrawn.
///
/// One id, replaced each time, so there is never more than one pending.
class ScheduleBackupReminder implements UseCase<Unit, DateTime> {
  /// Creates the use case.
  const ScheduleBackupReminder(this._repository, this._notifier);

  final BackupRepository _repository;
  final LocalNotifier _notifier;

  /// How long without a backup before the reminder.
  static const Duration interval = Duration(days: 7);

  /// When an overdue reminder comes: the next 9:00.
  static const int overdueHour = 9;

  /// What tapping the reminder opens: the backup rows in Settings.
  static const String payload = 'backup-reminder';

  @override
  Future<Either<Failure, Unit>> call(DateTime params) async {
    final now = params;
    switch (await _repository.status(now)) {
      case Left(value: final failure):
        return Left(failure);
      case Right(value: final status) when status.transactionCount == 0:
        return _notifier.cancel(AppNotification.backupReminderId);
      case Right(value: final status):
        final base = (status.lastSavedAt ?? status.firstSeenAt).toLocal();
        final due = dueAt(base, now);
        return _notifier.schedule(
          AppNotification(
            id: AppNotification.backupReminderId,
            kind: NotificationKind.backupReminder,
            title: 'Time for a backup',
            body: status.lastSavedAt == null
                ? 'Nothing on this phone has been backed up yet. A backup is '
                      'the only copy that survives losing it.'
                : 'Your last backup was a week or more ago. Save a new one '
                      'from Settings.',
            payload: payload,
          ),
          due,
        );
    }
  }

  /// When the reminder for a backup made at [base] is shown, as of [now].
  static DateTime dueAt(DateTime base, DateTime now) {
    final due = base.add(interval);
    if (due.isAfter(now)) return due;
    final today = DateTime(now.year, now.month, now.day, overdueHour);
    return today.isAfter(now) ? today : today.add(const Duration(days: 1));
  }
}
