import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/recurring_rule_repository.dart';

/// Stops a recurring rule posting, keeping everything it posted.
/// FR-EXP-008, FR-INC-004.
///
/// Pausing is not deleting: the rule, its schedule and its template stay,
/// so resuming (`ResumeRecurringRule`) picks up where the schedule stands
/// on the day it resumes. Pausing a rule that is already stopped changes
/// nothing and is not refused — the list only offers it on a running rule,
/// and a second tap arriving after the first is not an error.
class PauseRecurringRule implements UseCase<Unit, int> {
  /// Creates the use case.
  const PauseRecurringRule(this._repository);

  final RecurringRuleRepository _repository;

  /// Pauses the rule whose id is [params].
  @override
  Future<Either<Failure, Unit>> call(int params) => _repository.pause(params);
}
