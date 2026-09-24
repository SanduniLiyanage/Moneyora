import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/local_notifier.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/settings_repository.dart';

/// Turns FR-SET-007's budget alerts on or off. [params] is the new state.
///
/// **On asks the platform first**, and stores nothing unless it may
/// notify: a setting that reads "on" over a permission the user refused
/// would promise alerts that never arrive. The refusal is a
/// [PermissionFailure] whose sentence says where the permission is now —
/// on Android 13 and iOS a second prompt is not shown once the user has
/// said no, so the phone's own settings are the only way back.
///
/// **Off asks nothing** and cannot be refused.
class SetBudgetAlerts implements UseCase<Unit, bool> {
  /// Creates the use case over [repository] and [notifier].
  const SetBudgetAlerts(this._repository, this._notifier);

  final SettingsRepository _repository;
  final LocalNotifier _notifier;

  /// The sentence for a refused permission.
  static const String refusedMessage =
      'Notifications are turned off for Moneyora. Allow them in your '
      "phone's settings, then turn budget alerts on again.";

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
      (settings) =>
          _repository.save(settings.copyWith(budgetAlertsEnabled: params)),
    );
  }
}
