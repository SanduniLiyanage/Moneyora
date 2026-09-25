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
  Future<Either<Failure, List<RecurringSeries>>> due(DateTime today);

  /// Every rule, active and stopped, each with its template, kept live.
  ///
  /// Re-read on every write to the ledger, not only to the rules: a
  /// catch-up moving a due date, an edit changing a template's amount, and
  /// a delete handing a template on (E-36) all change what the list shows.
  Stream<Either<Failure, List<RecurringSeries>>> watchAll();

  /// Stops rule [ruleId] posting. Its entries stay; nothing else changes.
  Future<Either<Failure, Unit>> pause(int ruleId);

  /// Starts rule [ruleId] posting again, next due on [nextDueDate].
  Future<Either<Failure, Unit>> resume(int ruleId, DateTime nextDueDate);

  /// Deletes rule [ruleId], keeping every entry it posted. E-36.
  ///
  /// The entries are unlinked first — `recurring_rule_id` cleared,
  /// `is_recurring` kept, so each still reads as generated — then the rule
  /// goes, in one database transaction.
  Future<Either<Failure, Unit>> delete(int ruleId);

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
