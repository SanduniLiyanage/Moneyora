import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/recurring_rule_repository.dart';

/// Deletes a recurring rule and keeps every entry it posted. FR-EXP-008,
/// FR-INC-004, E-36.
///
/// The entries are money that moved; deleting the rule says "stop", not
/// "it never happened". They stay in the ledger, unlinked from the rule and
/// still marked as generated — which is what `Transaction.isRecurring` is
/// kept beside the rule's id for. A user who also wants an entry gone
/// deletes it from the list, where Undo covers it (E-23).
class DeleteRecurringRule implements UseCase<Unit, int> {
  /// Creates the use case.
  const DeleteRecurringRule(this._repository);

  final RecurringRuleRepository _repository;

  /// Deletes the rule whose id is [params].
  @override
  Future<Either<Failure, Unit>> call(int params) => _repository.delete(params);
}
