import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/recurring_rule_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/post_due_recurring_transactions.dart';

class _Post {
  _Post({
    required this.ruleId,
    required this.expectedNextDueDate,
    required this.entries,
    required this.nextDueDate,
    required this.ended,
    required this.postedAt,
  });

  final int ruleId;
  final DateTime expectedNextDueDate;
  final List<Transaction> entries;
  final DateTime nextDueDate;
  final bool ended;
  final DateTime postedAt;
}

class _FakeRules implements RecurringRuleRepository {
  Either<Failure, List<DueRecurringRule>> dueResult = const Right([]);
  DateTime? askedAbout;
  final posts = <_Post>[];

  /// Rules whose post fails, as a compare-and-set that lost would.
  final failing = <int, Failure>{};

  @override
  Future<Either<Failure, List<DueRecurringRule>>> due(DateTime today) async {
    askedAbout = today;
    return dueResult;
  }

  @override
  Future<Either<Failure, List<int>>> post({
    required int ruleId,
    required DateTime expectedNextDueDate,
    required List<Transaction> entries,
    required DateTime nextDueDate,
    required bool ended,
    required DateTime postedAt,
  }) async {
    if (failing[ruleId] case final failure?) return Left(failure);
    posts.add(
      _Post(
        ruleId: ruleId,
        expectedNextDueDate: expectedNextDueDate,
        entries: entries,
        nextDueDate: nextDueDate,
        ended: ended,
        postedAt: postedAt,
      ),
    );
    return Right([for (var i = 0; i < entries.length; i++) 100 + i]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeAccounts implements AccountReader {
  Either<Failure, List<AccountOption>> result = const Right([
    AccountOption(id: 1, name: 'Cash', balanceCents: 0),
    AccountOption(id: 2, name: 'Bank', balanceCents: 0),
  ]);
  var reads = 0;

  @override
  Stream<Either<Failure, List<AccountOption>>> watchAll() {
    reads++;
    return Stream.value(result);
  }
}

void main() {
  late _FakeRules rules;
  late _FakeAccounts accounts;
  late PostDueRecurringTransactions postDue;

  // Well inside the past, so AddTransaction's future-date rule — which
  // reads the real clock — never refuses an entry here.
  final now = DateTime(2026, 4, 20, 8, 15);

  Transaction template({
    int accountId = 1,
    TransactionType type = TransactionType.expense,
    int? categoryId = 7,
    TransferDirection? direction,
    List<TransactionSplit> splits = const [],
  }) => Transaction(
    id: 9,
    accountId: accountId,
    categoryId: categoryId,
    amountCents: 4500000,
    type: type,
    transferDirection: direction,
    date: DateTime(2026, 1, 5),
    time: '09:00',
    note: 'Rent',
    splits: splits,
    recurringRuleId: 5,
    isRecurring: true,
  );

  RecurringRule monthly({int id = 5, DateTime? next, DateTime? end}) =>
      RecurringRule(
        id: id,
        templateTransactionId: 9,
        frequency: RecurrenceFrequency.monthly,
        dayOfMonth: 5,
        startDate: DateTime(2026, 1, 5),
        nextDueDate: next ?? DateTime(2026, 2, 5),
        endDate: end,
      );

  setUp(() {
    rules = _FakeRules();
    accounts = _FakeAccounts();
    postDue = PostDueRecurringTransactions(rules, accounts);
  });

  test('nothing due reads no accounts and posts nothing', () async {
    final result = await postDue(now);

    expect(
      result,
      const Right<Failure, RecurringPostingReport>(
        RecurringPostingReport.nothing,
      ),
    );
    expect(rules.askedAbout, now);
    expect(accounts.reads, 0);
    expect(rules.posts, isEmpty);
  });

  test('posts every missed entry, copied from the template, and moves the '
      'rule on compare-and-set', () async {
    rules.dueResult = Right([
      DueRecurringRule(rule: monthly(), template: template()),
    ]);

    final result = await postDue(now);

    expect(
      result,
      const Right<Failure, RecurringPostingReport>(
        RecurringPostingReport(postedCount: 3, failures: []),
      ),
    );
    final post = rules.posts.single;
    expect(post.ruleId, 5);
    expect(post.expectedNextDueDate, DateTime(2026, 2, 5));
    expect(post.entries.map((e) => e.date), [
      DateTime(2026, 2, 5),
      DateTime(2026, 3, 5),
      DateTime(2026, 4, 5),
    ]);
    for (final e in post.entries) {
      expect(e.id, isNull);
      expect(e.accountId, 1);
      expect(e.categoryId, 7);
      expect(e.amountCents, 4500000);
      expect(e.type, TransactionType.expense);
      expect(e.time, '09:00');
      expect(e.note, 'Rent');
      expect(e.recurringRuleId, 5);
      expect(e.isRecurring, isTrue);
    }
    expect(post.nextDueDate, DateTime(2026, 5, 5));
    expect(post.ended, isFalse);
    expect(post.postedAt, now);
  });

  test('a rule reaching its end posts up to it and ends', () async {
    rules.dueResult = Right([
      DueRecurringRule(
        rule: monthly(end: DateTime(2026, 3, 31)),
        template: template(),
      ),
    ]);

    await postDue(now);

    final post = rules.posts.single;
    expect(post.entries.map((e) => e.date), [
      DateTime(2026, 2, 5),
      DateTime(2026, 3, 5),
    ]);
    expect(post.ended, isTrue);
  });

  test('a rule already past its end is stopped with nothing posted', () async {
    rules.dueResult = Right([
      DueRecurringRule(
        rule: monthly(end: DateTime(2026, 2, 1)),
        template: template(),
      ),
    ]);

    final result = await postDue(now);

    expect(
      result,
      const Right<Failure, RecurringPostingReport>(
        RecurringPostingReport.nothing,
      ),
    );
    final post = rules.posts.single;
    expect(post.entries, isEmpty);
    expect(post.ended, isTrue);
  });

  group(
    'a rule that cannot post is left due and reported; the others post',
    () {
      Future<void> reportsOnly(
        DueRecurringRule broken,
        Failure expected,
      ) async {
        final healthy = DueRecurringRule(
          rule: monthly(id: 6),
          template: template(),
        );
        rules.dueResult = Right([broken, healthy]);

        final result = await postDue(now);

        expect(
          result,
          Right<Failure, RecurringPostingReport>(
            RecurringPostingReport(
              postedCount: 3,
              failures: [
                RecurringRuleFailure(
                  ruleId: broken.rule.id!,
                  failure: expected,
                ),
              ],
            ),
          ),
        );
        expect(rules.posts.map((p) => p.ruleId), [6]);
      }

      test('its account is archived', () async {
        await reportsOnly(
          DueRecurringRule(rule: monthly(), template: template(accountId: 3)),
          const ValidationFailure(
            'Its account is archived. Restore the account to post this repeat.',
          ),
        );
      });

      test('its template is gone (E-36)', () async {
        await reportsOnly(
          DueRecurringRule(rule: monthly(), template: null),
          const ValidationFailure(
            'The entry this repeat copied was deleted, so there is nothing '
            'left to copy.',
          ),
        );
      });

      test('its template was edited into a split', () async {
        await reportsOnly(
          DueRecurringRule(
            rule: monthly(),
            template: template(
              splits: const [
                TransactionSplit(categoryId: 7, amountCents: 2000000),
                TransactionSplit(categoryId: 8, amountCents: 2500000),
              ],
            ),
          ),
          const ValidationFailure(
            'Only an unsplit expense or income can repeat. Edit the first '
            'entry back to one to start it again.',
          ),
        );
      });

      test('it cannot be scheduled', () async {
        await reportsOnly(
          DueRecurringRule(
            rule: RecurringRule(
              id: 5,
              templateTransactionId: 9,
              frequency: RecurrenceFrequency.customDays,
              intervalDays: 0,
              startDate: DateTime(2026, 1, 5),
              nextDueDate: DateTime(2026, 1, 5),
            ),
            template: template(),
          ),
          const ValidationFailure(
            'A custom repeat needs an interval of at least one day.',
          ),
        );
      });

      test('its write fails, as a lost compare-and-set does', () async {
        rules.failing[5] = const CacheFailure('Already posted.');
        await reportsOnly(
          DueRecurringRule(rule: monthly(), template: template()),
          const CacheFailure('Already posted.'),
        );
      });
    },
  );

  test('income posts as income (FR-INC-004)', () async {
    rules.dueResult = Right([
      DueRecurringRule(
        rule: monthly(),
        template: template(type: TransactionType.income, categoryId: 3),
      ),
    ]);

    await postDue(now);

    expect(rules.posts.single.entries.map((e) => e.type).toSet(), {
      TransactionType.income,
    });
  });

  test('failing to read the due rules fails the run', () async {
    rules.dueResult = const Left(CacheFailure('Could not read.'));
    expect(
      await postDue(now),
      const Left<Failure, RecurringPostingReport>(
        CacheFailure('Could not read.'),
      ),
    );
  });

  test('failing to read the accounts fails the run, posting nothing', () async {
    rules.dueResult = Right([
      DueRecurringRule(rule: monthly(), template: template()),
    ]);
    accounts.result = const Left(CacheFailure('No accounts.'));

    expect(
      await postDue(now),
      const Left<Failure, RecurringPostingReport>(CacheFailure('No accounts.')),
    );
    expect(rules.posts, isEmpty);
  });

  test('reads the accounts once for the whole run', () async {
    rules.dueResult = Right([
      DueRecurringRule(rule: monthly(), template: template()),
      DueRecurringRule(rule: monthly(id: 6), template: template()),
    ]);

    await postDue(now);

    expect(accounts.reads, 1);
    expect(rules.posts, hasLength(2));
  });
}
