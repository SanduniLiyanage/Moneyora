import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/recurring_rule.dart';
import '../entities/transaction.dart';
import '../repositories/recurring_rule_repository.dart';
import 'add_transaction.dart';

/// Records an expense or income that repeats. FR-EXP-008, FR-INC-004.
///
/// The entry the user typed is written as the series' first entry and its
/// template, with the rule beside it, in one database transaction. The
/// rule's first due date is the occurrence after that entry, so nothing is
/// posted twice for the start date.
///
/// A start in the past is allowed — a rent that began three months ago —
/// and its missed entries are posted by the next catch-up
/// (`PostDueRecurringTransactions`), not here: one path posts entries, and
/// it is the one that moves the due date compare-and-set.
///
/// A start in the future is refused, because the template is a real entry
/// in the ledger and [AddTransaction.validate] refuses a future one.
class CreateRecurringRule implements UseCase<int, RecurringRuleRequest> {
  /// Creates the use case.
  const CreateRecurringRule(this._repository);

  final RecurringRuleRepository _repository;

  @override
  Future<Either<Failure, int>> call(RecurringRuleRequest params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);
    return _repository.create(first: params.first, rule: params.toRule());
  }

  /// Returns the reason [request] cannot repeat, or null if it can.
  ///
  /// Public and static, as [AddTransaction.validate] is, so the entry
  /// screen's recurring toggle can say why before the user saves.
  static ValidationFailure? validate(RecurringRuleRequest request) {
    if (AddTransaction.validate(request.first) case final failure?) {
      return failure;
    }
    // FR-EXP-008 and FR-INC-004 repeat expenses and income. A transfer is
    // neither, and is three rows a single template cannot copy (E-15).
    if (request.first.type == TransactionType.transfer) {
      return const ValidationFailure(
        'A transfer cannot repeat. Repeats are for expenses and income.',
      );
    }
    // A split's parts would each need copying and re-checking against the
    // total on every entry; the requirement does not ask for it.
    if (request.first.isSplit) {
      return const ValidationFailure(
        'A split expense cannot repeat. Save it as one category to make it '
        'repeat.',
      );
    }
    if (request.toRule().problem case final problem?) {
      return ValidationFailure(problem);
    }
    return null;
  }
}

/// What to repeat and how often. See [CreateRecurringRule].
class RecurringRuleRequest extends Equatable {
  /// Creates a request.
  const RecurringRuleRequest({
    required this.first,
    required this.frequency,
    this.intervalDays,
    this.endDate,
  });

  /// The first entry, which the rest copy. Its date is the series' start.
  final Transaction first;

  /// How often it repeats.
  final RecurrenceFrequency frequency;

  /// Days between entries, for [RecurrenceFrequency.customDays] only.
  final int? intervalDays;

  /// The last day an entry may fall on, inclusive. Null for open-ended.
  final DateTime? endDate;

  /// The rule this request describes, starting on [first]'s date.
  RecurringRule toRule() => RecurringRule.startingOn(
    first.date,
    frequency: frequency,
    intervalDays: intervalDays,
    endDate: endDate,
  );

  @override
  List<Object?> get props => [first, frequency, intervalDays, endDate];
}
