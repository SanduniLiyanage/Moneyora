import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/local_notifier.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

/// Turns FR-SET-006's recurring reminders on or off. [params] is the new
/// state. E-37.
///
/// The same shape as `SetBudgetAlerts`, for its reasons: **on asks the
/// platform first** and stores nothing unless it may notify, and the
/// refusal says where the permission lives now; **off asks nothing**. The
/// reminders themselves are scheduled and withdrawn by the transactions
/// feature's watcher, which follows this setting.
class SetRecurringReminders implements UseCase<Unit, bool> {
  /// Creates the use case over [repository] and [notifier].
  const SetRecurringReminders(this._repository, this._notifier);

  final SettingsRepository _repository;
  final LocalNotifier _notifier;

  /// The sentence for a refused permission.
  static const String refusedMessage =
      'Notifications are turned off for Moneyora. Allow them in your '
      "phone's settings, then turn recurring reminders on again.";

  @override
  Future<Either<Failure, Unit>> call(bool params) async {
    if (params) {
      final permitted = await _notifier.requestPermission();
      final refusal = permitted.fold<Failure?>(
        (failure) => failure,
        (granted) => granted ? null : const PermissionFailure(refusedMessage),
      );
      if (refusal != null) return Left(refusal);
    }

    final current = await _repository.get();
    return current.fold(
      Left.new,
      (settings) => _repository.save(
        settings.copyWith(recurringRemindersEnabled: params),
      ),
    );
  }
}
