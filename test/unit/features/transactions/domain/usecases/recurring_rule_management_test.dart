import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/recurring_rule_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/delete_recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/usecases/pause_recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/usecases/resume_recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/usecases/watch_recurring_rules.dart';

/// The rules list's four use cases: watch, pause, resume, delete.
/// FR-EXP-008, FR-INC-004.
class _FakeRules implements RecurringRuleRepository {
  _FakeRules(this.watched);

  final StreamController<Either<Failure, List<RecurringSeries>>> watched;
  final paused = <int>[];
  final resumed = <(int, DateTime)>[];
  final deleted = <int>[];
  Either<Failure, Unit> result = const Right(unit);

  @override
  Stream<Either<Failure, List<RecurringSeries>>> watchAll() => watched.stream;

  @override
  Future<Either<Failure, Unit>> pause(int ruleId) async {
    paused.add(ruleId);
    return result;
  }

  @override
  Future<Either<Failure, Unit>> resume(int ruleId, DateTime nextDueDate) async {
    resumed.add((ruleId, nextDueDate));
    return result;
  }

  @override
  Future<Either<Failure, Unit>> delete(int ruleId) async {
    deleted.add(ruleId);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakeRules rules;

  final today = DateTime(2026, 6, 20);

  RecurringRule monthly({
    int id = 5,
    DateTime? start,
    DateTime? next,
    DateTime? end,
    bool active = true,
    bool hasTemplate = true,
  }) => RecurringRule(
    id: id,
    templateTransactionId: hasTemplate ? 9 : null,
    frequency: RecurrenceFrequency.monthly,
    dayOfMonth: 5,
    startDate: start ?? DateTime(2026, 1, 5),
    nextDueDate: next ?? DateTime(2026, 7, 5),
    endDate: end,
    isActive: active,
  );

  RecurringSeries series(RecurringRule rule) => RecurringSeries(
    rule: rule,
    template: Transaction(
      id: 9,
      accountId: 1,
      categoryId: 7,
      amountCents: 100,
      type: TransactionType.expense,
      date: rule.startDate,
    ),
  );

  late StreamController<Either<Failure, List<RecurringSeries>>> watched;

  setUp(() {
    // Broadcast: closing a single-subscription controller nobody listened
    // to never completes, which would hang every test's tearDown.
    watched = StreamController.broadcast();
    rules = _FakeRules(watched);
  });
  tearDown(() => watched.close());

  group('WatchRecurringRules', () {
    test('rules that post come first, soonest first; then stopped ones, '
        'newest first', () {
      final soon = series(monthly(id: 1, next: DateTime(2026, 6, 25)));
      final later = series(monthly(id: 2, next: DateTime(2026, 8, 5)));
      final overdue = series(monthly(id: 3, next: DateTime(2026, 6, 5)));
      final pausedOld = series(
        monthly(id: 4, start: DateTime(2025, 1, 5), active: false),
      );
      final pausedNew = series(
        monthly(id: 5, start: DateTime(2026, 3, 5), active: false),
      );
      final ended = series(
        monthly(id: 6, start: DateTime(2026, 2, 5), end: DateTime(2026, 6, 1)),
      );

      final ordered = WatchRecurringRules.order([
        pausedOld,
        later,
        ended,
        soon,
        pausedNew,
        overdue,
      ], today);

      expect(ordered.map((s) => s.rule.id), [3, 1, 2, 5, 6, 4]);
    });

    test('passes each read through, ordered, and a failure as it is', () async {
      final seen = <Either<Failure, List<RecurringSeries>>>[];
      final sub = WatchRecurringRules(rules)(today).listen(seen.add);

      final a = series(monthly(id: 1, next: DateTime(2026, 9, 5)));
      final b = series(monthly(id: 2, next: DateTime(2026, 7, 5)));
      rules.watched
        ..add(Right([a, b]))
        ..add(const Left(CacheFailure('Could not read.')));
      await pumpEventQueue();

      expect(seen.first.getOrElse((f) => fail('$f')), [b, a]);
      expect(seen.last, isA<Left<Failure, List<RecurringSeries>>>());
      await sub.cancel();
    });
  });

  group('PauseRecurringRule', () {
    test('pauses the rule it is given', () async {
      expect(
        await PauseRecurringRule(rules)(5),
        const Right<Failure, Unit>(unit),
      );
      expect(rules.paused, [5]);
    });

    test('a repository failure comes back as it is', () async {
      rules.result = const Left(CacheFailure('Could not pause.'));
      expect(
        await PauseRecurringRule(rules)(5),
        const Left<Failure, Unit>(CacheFailure('Could not pause.')),
      );
    });
  });

  group('ResumeRecurringRule', () {
    Future<Either<Failure, Unit>> resume(RecurringRule rule) =>
        ResumeRecurringRule(rules)(ResumeRequest(rule: rule, today: today));

    test('steps over the paused stretch to the next date from today', () async {
      final result = await resume(
        monthly(next: DateTime(2026, 2, 5), active: false),
      );
      expect(result, const Right<Failure, Unit>(unit));
      expect(rules.resumed, [(5, DateTime(2026, 7, 5))]);
    });

    test('keeps an entry due today, for the catch-up to post', () async {
      await resume(
        monthly(
          next: DateTime(2026, 2, 5),
          active: false,
        ).copyWith(nextDueDate: DateTime(2026, 6, 20)),
      );
      expect(rules.resumed.single.$2, DateTime(2026, 6, 20));
    });

    Future<void> refused(RecurringRule rule, String message) async {
      expect(
        await resume(rule),
        Left<Failure, Unit>(ValidationFailure(message)),
      );
      expect(rules.resumed, isEmpty);
    }

    test('refuses a rule with no template (E-36)', () async {
      await refused(
        monthly(active: false, hasTemplate: false),
        'The entry this repeat copied was deleted, so there is nothing left '
        'to copy. Add the entry again with Repeat on.',
      );
    });

    test('refuses a rule whose next date from today is past its end', () async {
      await refused(
        monthly(
          next: DateTime(2026, 2, 5),
          end: DateTime(2026, 6, 30),
          active: false,
        ),
        'This repeat has ended, so it cannot resume.',
      );
    });

    test('allows a rule whose end is still ahead', () async {
      await resume(
        monthly(
          next: DateTime(2026, 2, 5),
          end: DateTime(2026, 7, 5),
          active: false,
        ),
      );
      expect(rules.resumed.single.$2, DateTime(2026, 7, 5));
    });

    test('refuses a rule that cannot be scheduled', () async {
      await refused(
        RecurringRule(
          id: 5,
          templateTransactionId: 9,
          frequency: RecurrenceFrequency.customDays,
          intervalDays: 0,
          startDate: DateTime(2026),
          nextDueDate: DateTime(2026),
          isActive: false,
        ),
        'A custom repeat needs an interval of at least one day.',
      );
    });

    test('refuses a rule that was never saved', () async {
      await refused(
        RecurringRule(
          frequency: RecurrenceFrequency.daily,
          startDate: DateTime(2026),
          nextDueDate: DateTime(2026, 1, 2),
        ),
        'That repeat has not been saved.',
      );
    });
  });

  group('DeleteRecurringRule', () {
    test('deletes the rule it is given', () async {
      expect(
        await DeleteRecurringRule(rules)(5),
        const Right<Failure, Unit>(unit),
      );
      expect(rules.deleted, [5]);
    });

    test('a repository failure comes back as it is', () async {
      rules.result = const Left(CacheFailure('Could not delete.'));
      expect(
        await DeleteRecurringRule(rules)(5),
        const Left<Failure, Unit>(CacheFailure('Could not delete.')),
      );
    });
  });
}
