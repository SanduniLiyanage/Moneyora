import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/local_notifier.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';
import 'package:moneyora/features/settings/domain/repositories/settings_repository.dart';
import 'package:moneyora/features/settings/domain/usecases/set_recurring_reminders.dart';
import 'package:moneyora/features/settings/domain/usecases/set_reminder_schedule.dart';

class _Repository implements SettingsRepository {
  UserSettings stored = const UserSettings();
  var saves = 0;

  @override
  Future<Either<Failure, UserSettings>> get() async => Right(stored);

  @override
  Future<Either<Failure, Unit>> save(UserSettings settings) async {
    stored = settings;
    saves++;
    return const Right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Notifier implements LocalNotifier {
  Either<Failure, bool> answer = const Right(true);
  var asked = 0;

  @override
  Future<Either<Failure, bool>> requestPermission() async {
    asked++;
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// FR-SET-006's two settings, E-37.
void main() {
  late _Repository repository;
  late _Notifier notifier;

  setUp(() {
    repository = _Repository();
    notifier = _Notifier();
  });

  group('SetRecurringReminders', () {
    test('on asks for permission, then stores it', () async {
      final result = await SetRecurringReminders(repository, notifier)(true);

      expect(result, const Right<Failure, Unit>(unit));
      expect(notifier.asked, 1);
      expect(repository.stored.recurringRemindersEnabled, isTrue);
    });

    test('a refused permission stores nothing and says where to go', () async {
      notifier.answer = const Right(false);

      expect(
        await SetRecurringReminders(repository, notifier)(true),
        const Left<Failure, Unit>(
          PermissionFailure(SetRecurringReminders.refusedMessage),
        ),
      );
      expect(repository.saves, 0);
    });

    test('off asks nothing', () async {
      repository.stored = const UserSettings(recurringRemindersEnabled: true);

      await SetRecurringReminders(repository, notifier)(false);

      expect(notifier.asked, 0);
      expect(repository.stored.recurringRemindersEnabled, isFalse);
    });

    test('leaves every other setting as it was', () async {
      repository.stored = const UserSettings(budgetAlertsEnabled: true);
      await SetRecurringReminders(repository, notifier)(true);
      expect(repository.stored.budgetAlertsEnabled, isTrue);
    });
  });

  group('SetReminderSchedule', () {
    test('stores the days and the time', () async {
      final result = await SetReminderSchedule(repository)(
        const ReminderSchedule(daysBefore: 2, minuteOfDay: 18 * 60),
      );
      expect(result, const Right<Failure, Unit>(unit));
      expect(repository.stored.reminderDaysBefore, 2);
      expect(repository.stored.reminderMinuteOfDay, 18 * 60);
    });

    test('accepts both ends of each range', () {
      for (final schedule in const [
        ReminderSchedule(daysBefore: 0, minuteOfDay: 0),
        ReminderSchedule(daysBefore: 7, minuteOfDay: 1439),
      ]) {
        expect(SetReminderSchedule.validate(schedule), isNull);
      }
    });

    test('refuses days outside 0 to 7 and a time outside the day', () async {
      expect(
        await SetReminderSchedule(repository)(
          const ReminderSchedule(daysBefore: 8, minuteOfDay: 540),
        ),
        const Left<Failure, Unit>(
          ValidationFailure(
            'A reminder can come on the day or up to 7 days before.',
          ),
        ),
      );
      expect(
        SetReminderSchedule.validate(
          const ReminderSchedule(daysBefore: -1, minuteOfDay: 540),
        ),
        isNotNull,
      );
      expect(
        SetReminderSchedule.validate(
          const ReminderSchedule(daysBefore: 1, minuteOfDay: 1440),
        ),
        const ValidationFailure('Choose a time of day.'),
      );
      expect(repository.saves, 0);
    });
  });
}
