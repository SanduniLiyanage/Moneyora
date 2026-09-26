import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/backup/domain/usecases/schedule_backup_reminder.dart';
import 'package:moneyora/features/backup/presentation/providers/backup_reminder_watcher.dart';
import 'package:moneyora/injection.dart';

/// FR-BAK-006: the reminder is rescheduled on launch and after every write.
void main() {
  late _CountingSchedule schedule;
  late ProviderContainer container;

  setUp(() {
    schedule = _CountingSchedule();
    container = ProviderContainer(
      overrides: [
        scheduleBackupReminderProvider.overrideWith((ref) async => schedule),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 27)),
      ],
    );
    addTearDown(container.dispose);
  });

  BackupReminderWatcher watch() {
    container.listen(backupReminderWatcherProvider, (_, _) {});
    return container.read(backupReminderWatcherProvider.notifier);
  }

  test('schedules once on launch, as of the clock', () async {
    await watch().idle;

    expect(schedule.runs, [DateTime(2026, 9, 27)]);
  });

  test('schedules again when the data changes', () async {
    final watcher = watch();
    await watcher.idle;

    container.read(databaseChangeBusProvider).notify();
    await Future<void>.delayed(Duration.zero);
    await watcher.idle;

    expect(schedule.runs, hasLength(2));
  });

  test('a burst of changes coalesces rather than running once each', () async {
    final watcher = watch();
    await watcher.idle;
    schedule.runs.clear();
    final bus = container.read(databaseChangeBusProvider);
    for (var i = 0; i < 5; i++) {
      bus.notify();
    }
    await Future<void>.delayed(Duration.zero);
    await watcher.idle;
    await watcher.idle;

    // The bus delivers each change in its own microtask, so a run can start
    // between two of them; what holds is that at most one ever waits.
    expect(schedule.runs.length, lessThan(5));
  });
}

class _CountingSchedule implements ScheduleBackupReminder {
  final List<DateTime> runs = [];

  @override
  Future<Either<Failure, Unit>> call(DateTime params) async {
    runs.add(params);
    return const Right(unit);
  }
}
