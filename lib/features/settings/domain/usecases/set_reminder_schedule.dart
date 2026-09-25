import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/notification_settings.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

/// Sets when recurring reminders come: how many days before the entry, and
/// at what time of day. FR-SET-006, E-37.
///
/// Refused outside the ranges the schema's CHECKs hold, in a sentence
/// rather than a constraint error. Changing it with reminders off is
/// allowed and stored: the user may set the time first and switch on
/// after.
class SetReminderSchedule implements UseCase<Unit, ReminderSchedule> {
  /// Creates the use case.
  const SetReminderSchedule(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(ReminderSchedule params) async {
    if (validate(params) case final failure?) return Left(failure);
    final current = await _repository.get();
    return current.fold(
      Left.new,
      (settings) => _repository.save(
        settings.copyWith(
          reminderDaysBefore: params.daysBefore,
          reminderMinuteOfDay: params.minuteOfDay,
        ),
      ),
    );
  }

  /// The reason [schedule] cannot be stored, or null.
  static ValidationFailure? validate(ReminderSchedule schedule) {
    const most = NotificationSettings.maxReminderDaysBefore;
    if (schedule.daysBefore < 0 || schedule.daysBefore > most) {
      return const ValidationFailure(
        'A reminder can come on the day or up to $most days before.',
      );
    }
    if (schedule.minuteOfDay < 0 || schedule.minuteOfDay >= 24 * 60) {
      return const ValidationFailure('Choose a time of day.');
    }
    return null;
  }
}

/// When recurring reminders come.
class ReminderSchedule extends Equatable {
  /// Creates a schedule.
  const ReminderSchedule({required this.daysBefore, required this.minuteOfDay});

  /// Days before the entry, 0 (the day itself) to 7.
  final int daysBefore;

  /// Minutes after midnight, 0 to 1439.
  final int minuteOfDay;

  @override
  List<Object?> get props => [daysBefore, minuteOfDay];
}
