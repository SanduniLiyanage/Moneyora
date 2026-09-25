import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/recurring_rule.dart';
import '../entities/transaction.dart';

/// What the app can do with recurring rules. FR-EXP-008, FR-INC-004.
///
/// Every write here also writes the ledger — the template, the entries a
/// catch-up posts — so each is one database transaction with the ledger
/// rows it carries, balances and plan spend moved inside it as for any
/// other transaction (E-18, FR-PLN-013). That is why the rules live in the
/// transactions feature rather than one of their own: a second feature
/// could not share the transaction.
abstract interface class RecurringRuleRepository {
  /// Writes [first] and [rule] together, linked both ways, and returns the
  /// rule's id.
  ///
  /// [first] is the template and the series' first entry; [rule]'s
  /// `templateTransactionId` and `id` are ignored and assigned here. Both
  /// rows or neither: a template with no rule is an expense that was meant
  /// to repeat and will not, and a rule with no template has nothing to
  /// copy.
  Future<Either<Failure, int>> create({
    required Transaction first,
    required RecurringRule rule,
  });

  /// Every active rule whose next entry falls on or before [today], with
  /// its template, oldest due date first.
  Future<Either<Failure, List<DueRecurringRule>>> due(DateTime today);

  /// Posts [entries] for rule [ruleId] and moves its next due date to
  /// [nextDueDate], in one database transaction. Returns the entries' ids.
  ///
  /// **Compare-and-set.** The rule moves only if its next due date is still
  /// [expectedNextDueDate] — the one the entries were computed from. When
  /// it is not, another catch-up got there first; nothing is written and
  /// the result is a failure, so an entry is never posted twice. [ended]
  /// stops the rule in the same write. [postedAt] is recorded as the last
  /// time it posted, when [entries] is not empty.
  Future<Either<Failure, List<int>>> post({
    required int ruleId,
    required DateTime expectedNextDueDate,
    required List<Transaction> entries,
    required DateTime nextDueDate,
    required bool ended,
    required DateTime postedAt,
  });
}
