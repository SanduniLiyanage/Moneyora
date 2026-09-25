import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/account_reader.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/recurring_rule.dart';
import '../entities/transaction.dart';
import '../repositories/recurring_rule_repository.dart';
import 'add_transaction.dart';

/// Posts every recurring entry that has fallen due. FR-EXP-008, FR-INC-004.
///
/// Run on launch and on resume, with the clock's `now` as its parameter.
/// For each active rule due on or before today it posts **every** missed
/// entry — no cap, because the ledger should say what happened — through
/// [AddTransaction.validate] and the same insert path a typed entry takes,
/// so balances and plan spend move with them (E-18, FR-PLN-013).
///
/// **Rules are independent.** Each is posted in its own database
/// transaction, with its due date moved compare-and-set inside it, so one
/// rule failing leaves the others posted and a run racing another posts
/// each entry once. A rule that cannot post is **left due**, untouched,
/// and named in the report; the next run tries it again, and the rules
/// list shows it as overdue in the meantime. It is not paused on the
/// user's behalf: the cause is usually something they can fix — an
/// archived account — and a rule switched off quietly is one they stop
/// expecting.
///
/// Only a failure to read the due rules at all, or the accounts, fails the
/// whole run.
class PostDueRecurringTransactions
    implements UseCase<RecurringPostingReport, DateTime> {
  /// Creates the use case.
  const PostDueRecurringTransactions(this._rules, this._accounts);

  final RecurringRuleRepository _rules;
  final AccountReader _accounts;

  @override
  Future<Either<Failure, RecurringPostingReport>> call(DateTime params) async {
    final now = params;

    final List<DueRecurringRule> due;
    switch (await _rules.due(now)) {
      case Left(value: final failure):
        return Left(failure);
      case Right(value: final rules):
        due = rules;
    }
    // The common case on launch, and it must stay one indexed query.
    if (due.isEmpty) return const Right(RecurringPostingReport.nothing);

    // Every account that is not archived. Read once for the run, not per
    // rule.
    final Set<int> openAccounts;
    switch (await _accounts.watchAll().first) {
      case Left(value: final failure):
        return Left(failure);
      case Right(value: final accounts):
        openAccounts = {for (final account in accounts) account.id};
    }

    var posted = 0;
    final failures = <RecurringRuleFailure>[];
    for (final item in due) {
      switch (await _catchUp(item, openAccounts, now)) {
        case Left(value: final failure):
          failures.add(
            RecurringRuleFailure(ruleId: item.rule.id!, failure: failure),
          );
        case Right(value: final count):
          posted += count;
      }
    }
    return Right(
      RecurringPostingReport(postedCount: posted, failures: failures),
    );
  }

  /// Posts [item]'s due entries, returning how many.
  Future<Either<Failure, int>> _catchUp(
    DueRecurringRule item,
    Set<int> openAccounts,
    DateTime now,
  ) async {
    final rule = item.rule;
    if (rule.problem case final problem?) {
      return Left(ValidationFailure(problem));
    }

    final template = item.template;
    if (template == null) {
      return const Left(
        ValidationFailure(
          'The entry this repeat copied was deleted, so there is nothing '
          'left to copy.',
        ),
      );
    }
    // Refused at creation too; checked again because the template is an
    // ordinary row that can be edited afterwards.
    if (template.type == TransactionType.transfer || template.isSplit) {
      return const Left(
        ValidationFailure(
          'Only an unsplit expense or income can repeat. Edit the first '
          'entry back to one to start it again.',
        ),
      );
    }
    // An archived account is hidden from every active view (FR-ACC-004),
    // so money posted to it would move a balance nobody is shown.
    if (!openAccounts.contains(template.accountId)) {
      return const Left(
        ValidationFailure(
          'Its account is archived. Restore the account to post this '
          'repeat.',
        ),
      );
    }

    final catchUp = rule.catchUp(now);
    final entries = [
      for (final date in catchUp.dates) rule.entryOn(date, template),
    ];
    for (final entry in entries) {
      if (AddTransaction.validate(entry) case final failure?) {
        return Left(failure);
      }
    }

    final written = await _rules.post(
      ruleId: rule.id!,
      expectedNextDueDate: rule.nextDueDate,
      entries: entries,
      nextDueDate: catchUp.nextDueDate,
      ended: catchUp.ended,
      postedAt: now,
    );
    return written.map((ids) => ids.length);
  }
}

/// What a catch-up did. See [PostDueRecurringTransactions].
class RecurringPostingReport extends Equatable {
  /// Creates a report.
  const RecurringPostingReport({
    required this.postedCount,
    required this.failures,
  });

  /// A run with nothing due.
  static const nothing = RecurringPostingReport(postedCount: 0, failures: []);

  /// Entries posted, across every rule.
  final int postedCount;

  /// Every rule that was due and could not post, with why.
  final List<RecurringRuleFailure> failures;

  @override
  List<Object?> get props => [postedCount, failures];
}

/// One rule a catch-up could not post, and why.
class RecurringRuleFailure extends Equatable {
  /// Creates a rule failure.
  const RecurringRuleFailure({required this.ruleId, required this.failure});

  /// The rule, left due.
  final int ruleId;

  /// Why it did not post.
  final Failure failure;

  @override
  List<Object?> get props => [ruleId, failure];
}
