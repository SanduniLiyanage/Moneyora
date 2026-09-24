import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/local_notifier.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/budget_alert_evaluation.dart';
import '../entities/budget_alert_level.dart';
import '../entities/money_plan.dart';
import '../repositories/money_plan_repository.dart';

/// What [CheckBudgetAlerts] reads: the active plan as it is now, and
/// whether the user wants to hear about it.
class BudgetAlertCheck extends Equatable {
  /// Creates the input.
  const BudgetAlertCheck({required this.plan, required this.alertsEnabled});

  /// The plan to check, or null when none is active.
  final MoneyPlan? plan;

  /// FR-SET-007's setting.
  final bool alertsEnabled;

  @override
  List<Object?> get props => [plan, alertsEnabled];
}

/// Announces every category of the active plan that has crossed 80% or 100%
/// of its allocation since it was last announced. FR-SET-007, E-35.
///
/// Run on every re-read of the active plan — after every transaction write,
/// an adjustment, an activation — and after the setting is turned on. What
/// counts as a crossing is [BudgetAlertEvaluation]'s; this use case stores
/// it and says it.
///
/// **Alerts off means nothing is evaluated**, not that crossings are
/// recorded silently. Turning alerts on while a category is already at 85%
/// then announces it once — true, and what the user just asked to hear —
/// the same reasoning that announces a plan activated past a threshold.
///
/// **The levels are stored before anything is shown, and only what the
/// store moved is shown.** A notification the platform refuses after the
/// store is lost; one shown before a store that then fails would be shown
/// again on the next write, and again after that for as long as the store
/// kept failing. And the store is compare-and-set
/// ([MoneyPlanRepository.recordAlertLevels]): an evaluation of a stale
/// read, racing another over the same crossing, finds the row already
/// moved and says nothing. Announcing once at most is the promise the
/// stored level exists to keep, so it is kept in both cases.
class CheckBudgetAlerts
    implements UseCase<List<BudgetAlert>, BudgetAlertCheck> {
  /// Creates the use case over [repository] and [notifier].
  const CheckBudgetAlerts(this._repository, this._notifier);

  final MoneyPlanRepository _repository;
  final LocalNotifier _notifier;

  /// The payload an alert carries, so tapping it opens the plan it is about.
  static const String payload = 'budget-alert';

  @override
  Future<Either<Failure, List<BudgetAlert>>> call(
    BudgetAlertCheck params,
  ) async {
    final plan = params.plan;
    if (!params.alertsEnabled || plan == null || !plan.isActive) {
      return const Right(<BudgetAlert>[]);
    }

    final evaluation = BudgetAlertEvaluation.of(plan);
    if (evaluation.isUnchanged) return const Right(<BudgetAlert>[]);

    final stored = await _repository.recordAlertLevels(evaluation.changes);
    return stored.fold(Left.new, (moved) async {
      final announced = [
        for (final alert in evaluation.alerts)
          if (moved.contains(alert.allocationId)) alert,
      ];
      Failure? firstRefusal;
      for (final alert in announced) {
        final shown = await _notifier.show(notificationFor(alert, plan));
        // Every alert is attempted: one refused is no reason to hold back
        // the rest, and their levels are already stored.
        firstRefusal ??= shown.fold((failure) => failure, (_) => null);
      }
      return firstRefusal == null ? Right(announced) : Left(firstRefusal);
    });
  }

  /// What [alert] says on [plan]'s behalf.
  ///
  /// Percentages rather than amounts: the plan's figures are in the base
  /// currency, and formatting money is `currency_utils.dart`'s job, which
  /// the domain does not reach. The percentage is the tracking bar's own.
  static AppNotification notificationFor(BudgetAlert alert, MoneyPlan plan) {
    final name = alert.categoryName;
    final percent = alert.percentUsed;
    return AppNotification(
      id: AppNotification.budgetAlertBase + alert.allocationId,
      kind: NotificationKind.budgetAlert,
      title: switch (alert.level) {
        BudgetAlertLevel.warning => '$name is at $percent% of its budget',
        BudgetAlertLevel.exceeded when percent <= 100 =>
          '$name has used its whole budget',
        BudgetAlertLevel.exceeded => '$name is over budget, at $percent%',
        // Never announced: an evaluation only alerts upward.
        BudgetAlertLevel.none => name,
      },
      body: switch (alert.level) {
        BudgetAlertLevel.exceeded =>
          'In your "${plan.name}" plan. Open it to redistribute, adjust or '
              'carry the overspend over.',
        _ => 'In your "${plan.name}" plan. Open it to see what is left.',
      },
      payload: payload,
    );
  }
}
