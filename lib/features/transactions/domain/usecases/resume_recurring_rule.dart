import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/recurring_rule.dart';
import '../repositories/recurring_rule_repository.dart';

/// Starts a paused recurring rule posting again. FR-EXP-008, FR-INC-004.
///
/// **The paused stretch is stepped over, not posted.** The rule's next due
/// date moves to the first date it falls on from today
/// ([RecurringRule.nextOnOrAfter]); the entries that fell due while it was
/// paused are the ones the user paused it to stop. An entry due today is
/// posted by the next catch-up, which the screen runs after resuming.
///
/// Refused when there is nothing to resume: a rule whose template was
/// deleted with nothing to take over (E-36), and a rule whose next date
/// from today is past its end.
class ResumeRecurringRule implements UseCase<Unit, ResumeRequest> {
  /// Creates the use case.
  const ResumeRecurringRule(this._repository);

  final RecurringRuleRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(ResumeRequest params) async {
    final rule = params.rule;
    final id = rule.id;
    if (id == null) {
      return const Left(ValidationFailure('That repeat has not been saved.'));
    }
    if (rule.problem case final problem?) {
      return Left(ValidationFailure(problem));
    }
    if (rule.templateTransactionId == null) {
      return const Left(
        ValidationFailure(
          'The entry this repeat copied was deleted, so there is nothing '
          'left to copy. Add the entry again with Repeat on.',
        ),
      );
    }
    final next = rule.nextOnOrAfter(params.today);
    final end = rule.endDate;
    if (end != null && next.isAfter(end)) {
      return const Left(
        ValidationFailure('This repeat has ended, so it cannot resume.'),
      );
    }
    return _repository.resume(id, next);
  }
}

/// Which rule to resume, and the day it resumes on.
class ResumeRequest extends Equatable {
  /// Creates a request.
  const ResumeRequest({required this.rule, required this.today});

  /// The rule, as the list last read it.
  final RecurringRule rule;

  /// Today, from the clock the screen reads.
  final DateTime today;

  @override
  List<Object?> get props => [rule, today];
}
