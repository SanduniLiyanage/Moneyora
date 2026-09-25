import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/repositories/recurring_rule_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/post_due_recurring_transactions.dart';
import 'package:moneyora/features/transactions/presentation/providers/recurring_catch_up.dart';
import 'package:moneyora/injection.dart';

/// Counts the runs by the one read every run makes, and can hold a run
/// open to see what arrives meanwhile.
class _Rules implements RecurringRuleRepository {
  final asked = <DateTime>[];
  Completer<void>? hold;

  @override
  Future<Either<Failure, List<DueRecurringRule>>> due(DateTime today) async {
    asked.add(today);
    await hold?.future;
    return const Right([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Accounts implements AccountReader {
  @override
  Stream<Either<Failure, List<AccountOption>>> watchAll() =>
      Stream.value(const Right([]));
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late _Rules rules;
  late ProviderContainer container;
  final now = DateTime(2026, 4, 20, 8, 15);

  ProviderContainer start({bool buildFails = false}) {
    final c = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(() => now),
        postDueRecurringTransactionsProvider.overrideWith(
          (ref) async => buildFails
              ? throw StateError('The database did not open.')
              : PostDueRecurringTransactions(rules, _Accounts()),
        ),
      ],
    )..listen(recurringCatchUpProvider, (_, _) {});
    return c;
  }

  Future<void> idle() => container.read(recurringCatchUpProvider.notifier).idle;

  void resume() {
    // The listener reports a resume on the way back up from the background.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    rules = _Rules();
    container = start();
  });

  tearDown(() => container.dispose());

  test('runs once on launch, with the clock', () async {
    await idle();
    expect(rules.asked, [now]);
  });

  test('runs again on every resume', () async {
    await idle();
    resume();
    await idle();
    resume();
    await idle();
    expect(rules.asked, hasLength(3));
  });

  test('a run already waiting absorbs the next request', () async {
    rules.hold = Completer<void>();
    await pumpEventQueue();
    expect(rules.asked, hasLength(1), reason: 'the launch run is in flight');

    final catchUp = container.read(recurringCatchUpProvider.notifier)
      ..run() // queued behind the launch run
      ..run() // absorbed: one is already waiting
      ..run();
    rules.hold!.complete();
    rules.hold = null;
    await catchUp.idle;

    expect(rules.asked, hasLength(2));
  });

  test('a use case that cannot be built is logged, and the next run still '
      'goes', () async {
    container.dispose();
    container = start(buildFails: true);
    await idle();
    expect(rules.asked, isEmpty);

    container.read(recurringCatchUpProvider.notifier).run();
    await idle();
    expect(rules.asked, isEmpty, reason: 'still cannot be built');
    // Reaching here without an unhandled error is the assertion: a failed
    // run must not poison the queue behind it.
  });

  test('stops listening for resumes once disposed', () async {
    await idle();
    container.dispose();
    resume();
    await pumpEventQueue();
    expect(rules.asked, hasLength(1));
    // tearDown disposes again, which Riverpod allows.
  });
}
