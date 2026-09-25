import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/local_notifier.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_evaluation.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_level.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/check_budget_alerts.dart';

/// Records the levels it was asked to store, in order with what was shown.
///
/// Every change moves its row unless its id is in [alreadyMoved] — a row
/// another evaluation got to first, as the real compare-and-set reports it.
class _FakeRepository implements MoneyPlanRepository {
  _FakeRepository(this.log);

  final List<String> log;
  Map<int, BudgetAlertLevel>? recorded;
  Failure? recordFails;
  Set<int> alreadyMoved = {};

  @override
  Future<Either<Failure, Set<int>>> recordAlertLevels(
    List<AlertLevelChange> changes,
  ) async {
    log.add('record');
    if (recordFails case final f?) return Left(f);
    recorded = {for (final c in changes) c.allocationId: c.to};
    return Right({
      for (final c in changes)
        if (!alreadyMoved.contains(c.allocationId)) c.allocationId,
    });
  }

  @override
  Future<Either<Failure, Unit>> activate(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getLatestEndingBefore(DateTime day) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> recomputeSpent(int planId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations,
  ) => throw UnimplementedError();

  @override
  Stream<Either<Failure, MoneyPlan?>> watchActive() =>
      throw UnimplementedError();

  @override
  Stream<Either<Failure, List<MoneyPlan>>> watchAll() =>
      throw UnimplementedError();
}

class _FakeNotifier implements LocalNotifier {
  _FakeNotifier(this.log);

  final List<String> log;
  final List<AppNotification> shown = [];

  /// Refuses the show of any notification whose id is in here.
  final Map<int, Failure> refuse = {};

  @override
  Future<Either<Failure, Unit>> show(AppNotification notification) async {
    log.add('show ${notification.id}');
    if (refuse[notification.id] case final f?) return Left(f);
    shown.add(notification);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, bool>> requestPermission() =>
      throw UnimplementedError();

  // Scheduling (FR-SET-006) is not exercised here; a call fails loudly.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

PlanAllocation _row(
  int id,
  String name, {
  required int allocated,
  required int spent,
  BudgetAlertLevel alerted = BudgetAlertLevel.none,
}) => PlanAllocation(
  id: id,
  categoryId: id,
  categoryName: name,
  allocatedCents: allocated,
  spentCents: spent,
  confidence: ConfidenceLevel.medium,
  alertedLevel: alerted,
);

MoneyPlan _plan(List<PlanAllocation> rows, {bool isActive = true}) => MoneyPlan(
  id: 7,
  name: 'September',
  period: PlanPeriod.month(2026, 9),
  totalBudgetCents: rows.fold(0, (s, a) => s + a.allocatedCents),
  isActive: isActive,
  allocations: rows,
);

void main() {
  late List<String> log;
  late _FakeRepository repository;
  late _FakeNotifier notifier;
  late CheckBudgetAlerts check;

  setUp(() {
    log = [];
    repository = _FakeRepository(log);
    notifier = _FakeNotifier(log);
    check = CheckBudgetAlerts(repository, notifier);
  });

  final crossed = _plan([
    _row(1, 'Food', allocated: 10000, spent: 8500),
    _row(2, 'Transport', allocated: 5000, spent: 5200),
    _row(3, 'Health', allocated: 5000, spent: 100),
  ]);

  group('nothing is evaluated', () {
    test('while alerts are off — not even recorded silently', () async {
      final result = await check(
        BudgetAlertCheck(plan: crossed, alertsEnabled: false),
      );

      expect(result.getOrElse((_) => throw StateError('left')), isEmpty);
      expect(log, isEmpty);
    });

    test('when no plan is active', () async {
      final result = await check(
        const BudgetAlertCheck(plan: null, alertsEnabled: true),
      );

      expect(result.getOrElse((_) => throw StateError('left')), isEmpty);
      expect(log, isEmpty);
    });

    test('for a plan that is not the active one', () async {
      final result = await check(
        BudgetAlertCheck(
          plan: _plan(crossed.allocations, isActive: false),
          alertsEnabled: true,
        ),
      );

      expect(result.getOrElse((_) => throw StateError('left')), isEmpty);
      expect(log, isEmpty);
    });
  });

  test(
    'stores the new levels, then shows one notification per crossing',
    () async {
      final result = await check(
        BudgetAlertCheck(plan: crossed, alertsEnabled: true),
      );

      expect(
        result
            .getOrElse((_) => throw StateError('left'))
            .map((a) => a.allocationId),
        [1, 2],
      );
      expect(repository.recorded, {
        1: BudgetAlertLevel.warning,
        2: BudgetAlertLevel.exceeded,
      });
      expect(log, [
        'record',
        'show ${AppNotification.budgetAlertBase + 1}',
        'show ${AppNotification.budgetAlertBase + 2}',
      ]);
    },
  );

  test('writes nothing when nothing changed — which is what ends the loop '
      'its own write starts', () async {
    final result = await check(
      BudgetAlertCheck(
        plan: _plan([
          _row(
            1,
            'Food',
            allocated: 10000,
            spent: 8500,
            alerted: BudgetAlertLevel.warning,
          ),
        ]),
        alertsEnabled: true,
      ),
    );

    expect(result.getOrElse((_) => throw StateError('left')), isEmpty);
    expect(log, isEmpty);
  });

  test('a fall under a threshold is stored and shown to nobody', () async {
    await check(
      BudgetAlertCheck(
        plan: _plan([
          _row(
            1,
            'Food',
            allocated: 10000,
            spent: 1000,
            alerted: BudgetAlertLevel.exceeded,
          ),
        ]),
        alertsEnabled: true,
      ),
    );

    expect(repository.recorded, {1: BudgetAlertLevel.none});
    expect(notifier.shown, isEmpty);
  });

  test('a crossing another evaluation already stored is not announced '
      'again — the stale read loses the race', () async {
    repository.alreadyMoved = {1};

    final result = await check(
      BudgetAlertCheck(plan: crossed, alertsEnabled: true),
    );

    expect(
      result
          .getOrElse((_) => throw StateError('left'))
          .map((a) => a.allocationId),
      [2],
    );
    expect(notifier.shown.map((n) => n.id), [
      AppNotification.budgetAlertBase + 2,
    ]);
  });

  test('shows nothing when the levels cannot be stored, so a failing '
      'store cannot repeat an alert on every write', () async {
    repository.recordFails = const CacheFailure('disk full');

    final result = await check(
      BudgetAlertCheck(plan: crossed, alertsEnabled: true),
    );

    expect(
      result,
      const Left<Failure, List<BudgetAlert>>(CacheFailure('disk full')),
    );
    expect(log, ['record']);
  });

  test('one notification refused does not hold back the rest, and the '
      'refusal is returned', () async {
    notifier.refuse[AppNotification.budgetAlertBase + 1] =
        const PermissionFailure('blocked');

    final result = await check(
      BudgetAlertCheck(plan: crossed, alertsEnabled: true),
    );

    expect(
      result,
      const Left<Failure, List<BudgetAlert>>(PermissionFailure('blocked')),
    );
    expect(notifier.shown.map((n) => n.id), [
      AppNotification.budgetAlertBase + 2,
    ]);
    expect(repository.recorded, isNotNull);
  });

  group('what an alert says', () {
    AppNotification say(BudgetAlertLevel level, int percent) =>
        CheckBudgetAlerts.notificationFor(
          BudgetAlert(
            allocationId: 4,
            categoryName: 'Food',
            level: level,
            percentUsed: percent,
          ),
          crossed,
        );

    test('a warning gives the percentage and points at what is left', () {
      expect(
        say(BudgetAlertLevel.warning, 83),
        const AppNotification(
          id: AppNotification.budgetAlertBase + 4,
          kind: NotificationKind.budgetAlert,
          title: 'Food is at 83% of its budget',
          body: 'In your "September" plan. Open it to see what is left.',
          payload: CheckBudgetAlerts.payload,
        ),
      );
    });

    test('exactly spent says so, and names the three responses', () {
      final n = say(BudgetAlertLevel.exceeded, 100);

      expect(n.title, 'Food has used its whole budget');
      expect(
        n.body,
        'In your "September" plan. Open it to redistribute, adjust or '
        'carry the overspend over.',
      );
    });

    test('over says by how much', () {
      expect(
        say(BudgetAlertLevel.exceeded, 104).title,
        'Food is over budget, at 104%',
      );
    });

    test('the 100% alert replaces the 80% one for the same row', () {
      expect(
        say(BudgetAlertLevel.exceeded, 100).id,
        say(BudgetAlertLevel.warning, 80).id,
      );
    });
  });
}
