import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/transactions/data/datasources/recurring_rule_local_datasource.dart';
import 'package:moneyora/features/transactions/data/models/recurring_rule_model.dart';
import 'package:moneyora/features/transactions/data/models/transaction_model.dart';
import 'package:moneyora/features/transactions/data/repositories/recurring_rule_repository_impl.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';

class _FakeSource implements RecurringRuleLocalDataSource {
  List<RecurringSeriesRow> dueRows = const [];
  AppException? error;
  List<TransactionModel>? posted;
  TransactionModel? created;

  @override
  Future<int> create({
    required TransactionModel first,
    required RecurringRuleModel rule,
  }) async {
    if (error case final e?) throw e;
    created = first;
    return 3;
  }

  @override
  Future<List<RecurringSeriesRow>> due(DateTime today) async {
    if (error case final e?) throw e;
    return dueRows;
  }

  @override
  Future<List<int>> post({
    required int ruleId,
    required DateTime expectedNextDueDate,
    required List<TransactionModel> entries,
    required DateTime nextDueDate,
    required bool ended,
    required DateTime postedAt,
  }) async {
    if (error case final e?) throw e;
    posted = entries;
    return [for (var i = 0; i < entries.length; i++) i + 1];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakeSource source;
  late RecurringRuleRepositoryImpl repository;

  final rule = RecurringRule(
    id: 5,
    templateTransactionId: 9,
    frequency: RecurrenceFrequency.monthly,
    dayOfMonth: 5,
    startDate: DateTime(2026, 1, 5),
    nextDueDate: DateTime(2026, 2, 5),
  );
  final template = Transaction(
    id: 9,
    accountId: 1,
    categoryId: 7,
    amountCents: 100,
    type: TransactionType.expense,
    date: DateTime(2026, 1, 5),
  );

  setUp(() {
    source = _FakeSource();
    repository = RecurringRuleRepositoryImpl(source);
  });

  test('due hands up entities, not models', () async {
    source.dueRows = [
      (
        rule: RecurringRuleModel.fromEntity(rule),
        template: TransactionModel.fromEntity(template),
      ),
      (rule: RecurringRuleModel.fromEntity(rule), template: null),
    ];

    final result = await repository.due(DateTime(2026, 3));

    final due = result.getOrElse((f) => fail('$f'));
    expect(due, [
      RecurringSeries(rule: rule, template: template),
      RecurringSeries(rule: rule, template: null),
    ]);
    expect(due.first.rule.runtimeType, RecurringRule);
    expect(due.first.template.runtimeType, Transaction);
  });

  test('create and post pass entities down as models', () async {
    expect(
      await repository.create(first: template, rule: rule),
      const Right<Failure, int>(3),
    );
    expect(source.created, TransactionModel.fromEntity(template));

    final posted = await repository.post(
      ruleId: 5,
      expectedNextDueDate: DateTime(2026, 2, 5),
      entries: [template, template],
      nextDueDate: DateTime(2026, 3, 5),
      ended: false,
      postedAt: DateTime(2026, 3),
    );
    // Compared by contents: `Right` compares its value with `==`, and two
    // lists are never `==`.
    expect(posted.getOrElse((f) => fail('$f')), [1, 2]);
    expect(source.posted, hasLength(2));
  });

  test('a data-layer exception becomes a failure on every method', () async {
    source.error = const CacheException('Could not post.');
    const failure = CacheFailure('Could not post.');

    expect(
      await repository.create(first: template, rule: rule),
      const Left<Failure, int>(failure),
    );
    expect(
      await repository.due(DateTime(2026, 3)),
      const Left<Failure, List<RecurringSeries>>(failure),
    );
    expect(
      await repository.post(
        ruleId: 5,
        expectedNextDueDate: DateTime(2026, 2, 5),
        entries: const [],
        nextDueDate: DateTime(2026, 3, 5),
        ended: false,
        postedAt: DateTime(2026, 3),
      ),
      const Left<Failure, List<int>>(failure),
    );
  });
}
