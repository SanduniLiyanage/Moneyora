import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/recurring_rule_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/create_recurring_rule.dart';

class _FakeRepository implements RecurringRuleRepository {
  Transaction? first;
  RecurringRule? rule;
  Either<Failure, int> result = const Right(12);

  @override
  Future<Either<Failure, int>> create({
    required Transaction first,
    required RecurringRule rule,
  }) async {
    this.first = first;
    this.rule = rule;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakeRepository repository;
  late CreateRecurringRule create;

  final start = DateTime(2026, 1, 5);

  Transaction entry({
    TransactionType type = TransactionType.expense,
    int? categoryId = 7,
    int amountCents = 4500000,
    DateTime? date,
    TransferDirection? direction,
    List<TransactionSplit> splits = const [],
  }) => Transaction(
    accountId: 1,
    categoryId: categoryId,
    amountCents: amountCents,
    type: type,
    transferDirection: direction,
    date: date ?? start,
    note: 'Rent',
    splits: splits,
  );

  RecurringRuleRequest request({
    Transaction? first,
    RecurrenceFrequency frequency = RecurrenceFrequency.monthly,
    int? intervalDays,
    DateTime? endDate,
  }) => RecurringRuleRequest(
    first: first ?? entry(),
    frequency: frequency,
    intervalDays: intervalDays,
    endDate: endDate,
  );

  setUp(() {
    repository = _FakeRepository();
    create = CreateRecurringRule(repository);
  });

  test(
    'writes the entry and the rule it starts, next due one period on',
    () async {
      final result = await create(request());

      expect(result, const Right<Failure, int>(12));
      expect(repository.first, entry());
      expect(
        repository.rule,
        RecurringRule(
          frequency: RecurrenceFrequency.monthly,
          startDate: start,
          nextDueDate: DateTime(2026, 2, 5),
          dayOfMonth: 5,
        ),
      );
    },
  );

  test('income repeats as expenses do (FR-INC-004)', () async {
    final result = await create(
      request(
        first: entry(type: TransactionType.income, categoryId: 3),
        frequency: RecurrenceFrequency.weekly,
      ),
    );
    expect(result.isRight(), isTrue);
    expect(repository.rule!.dayOfWeek, start.weekday);
  });

  test('carries the end date and a custom interval', () async {
    await create(
      request(
        frequency: RecurrenceFrequency.customDays,
        intervalDays: 14,
        endDate: DateTime(2026, 6, 30),
      ),
    );
    expect(repository.rule!.intervalDays, 14);
    expect(repository.rule!.endDate, DateTime(2026, 6, 30));
    expect(repository.rule!.nextDueDate, DateTime(2026, 1, 19));
  });

  test('a repository failure comes back as it is', () async {
    repository.result = const Left(CacheFailure('Could not save.'));
    expect(
      await create(request()),
      const Left<Failure, int>(CacheFailure('Could not save.')),
    );
  });

  group('refuses, writing nothing', () {
    Future<void> refused(RecurringRuleRequest r, String message) async {
      expect(await create(r), Left<Failure, int>(ValidationFailure(message)));
      expect(repository.first, isNull);
      expect(CreateRecurringRule.validate(r), ValidationFailure(message));
    }

    test('an entry AddTransaction would refuse', () async {
      await refused(
        request(first: entry(amountCents: 0)),
        'Enter an amount greater than zero.',
      );
    });

    test('a start in the future, because the first entry is real', () async {
      await refused(
        request(
          first: entry(date: DateTime.now().add(const Duration(days: 40))),
        ),
        'That date is in the future.',
      );
    });

    test('a transfer', () async {
      await refused(
        request(
          first: entry(
            type: TransactionType.transfer,
            categoryId: null,
            direction: TransferDirection.out,
          ),
        ),
        'A transfer cannot repeat. Repeats are for expenses and income.',
      );
    });

    test('a split', () async {
      await refused(
        request(
          first: entry(
            amountCents: 300,
            splits: const [
              TransactionSplit(categoryId: 7, amountCents: 100),
              TransactionSplit(categoryId: 8, amountCents: 200),
            ],
          ),
        ),
        'A split expense cannot repeat. Save it as one category to make it '
        'repeat.',
      );
    });

    test('a monthly start past the 28th (E-03)', () async {
      await refused(
        request(first: entry(date: DateTime(2026, 1, 29))),
        'A monthly repeat can fall on the 1st to the 28th, so it lands in '
        'every month.',
      );
    });

    test('a custom repeat without a whole-day interval', () async {
      const message = 'A custom repeat needs an interval of at least one day.';
      await refused(
        request(frequency: RecurrenceFrequency.customDays),
        message,
      );
      await refused(
        request(frequency: RecurrenceFrequency.customDays, intervalDays: 0),
        message,
      );
    });

    test('an end before the start', () async {
      await refused(
        request(endDate: DateTime(2026, 1, 4)),
        'A repeat cannot end before it starts.',
      );
    });
  });

  test('a start on the 29th is fine for every frequency but monthly', () {
    for (final frequency in [
      RecurrenceFrequency.daily,
      RecurrenceFrequency.weekly,
      RecurrenceFrequency.yearly,
    ]) {
      expect(
        CreateRecurringRule.validate(
          request(
            first: entry(date: DateTime(2026, 1, 29)),
            frequency: frequency,
          ),
        ),
        isNull,
        reason: '$frequency',
      );
    }
  });
}
