import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/money_plan/domain/entities/allocation_progress.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_evaluation.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_level.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';

PlanAllocation _row(
  int id, {
  required int allocated,
  required int spent,
  BudgetAlertLevel alerted = BudgetAlertLevel.none,
  String? name = 'Food',
}) => PlanAllocation(
  id: id,
  categoryId: id,
  categoryName: name,
  allocatedCents: allocated,
  spentCents: spent,
  confidence: ConfidenceLevel.medium,
  alertedLevel: alerted,
);

MoneyPlan _plan(List<PlanAllocation> rows) => MoneyPlan(
  id: 7,
  name: 'September',
  period: PlanPeriod.month(2026, 9),
  totalBudgetCents: rows.fold(0, (s, a) => s + a.allocatedCents),
  isActive: true,
  allocations: rows,
);

BudgetAlertEvaluation _evaluate(List<PlanAllocation> rows) =>
    BudgetAlertEvaluation.of(_plan(rows));

void main() {
  group('levelOf reads the tracking bar\'s own bands', () {
    // 10,000 cents allocated: 7,999 is 79.99%, 8,000 exactly 80%.
    final cases = <(int, BudgetAlertLevel, TrackingStatus)>[
      (0, BudgetAlertLevel.none, TrackingStatus.onTrack),
      (7999, BudgetAlertLevel.none, TrackingStatus.onTrack),
      (8000, BudgetAlertLevel.warning, TrackingStatus.warning),
      (9999, BudgetAlertLevel.warning, TrackingStatus.warning),
      (10000, BudgetAlertLevel.exceeded, TrackingStatus.exceeded),
      (15000, BudgetAlertLevel.exceeded, TrackingStatus.exceeded),
    ];

    for (final (spent, level, status) in cases) {
      test('$spent of 10000 is $level, as the bar is $status', () {
        final row = _row(1, allocated: 10000, spent: spent);

        expect(BudgetAlertEvaluation.levelOf(row), level);
        expect(
          AllocationProgress.of(
            row,
            PlanPeriod.month(2026, 9),
            DateTime(2026, 9, 15),
          ).status,
          status,
        );
      });
    }

    test('an allocation of nothing is exceeded by any spend, and quiet '
        'without one', () {
      expect(
        BudgetAlertEvaluation.levelOf(_row(1, allocated: 0, spent: 1)),
        BudgetAlertLevel.exceeded,
      );
      expect(
        BudgetAlertEvaluation.levelOf(_row(1, allocated: 0, spent: 0)),
        BudgetAlertLevel.none,
      );
    });
  });

  group('upward', () {
    test('crossing 80% warns, with the floored percentage', () {
      final result = _evaluate([_row(1, allocated: 10000, spent: 8350)]);

      expect(result.alerts, const [
        BudgetAlert(
          allocationId: 1,
          categoryName: 'Food',
          level: BudgetAlertLevel.warning,
          percentUsed: 83,
        ),
      ]);
      expect(result.levels, {1: BudgetAlertLevel.warning});
    });

    test('crossing 100% after a warning alerts', () {
      final result = _evaluate([
        _row(
          1,
          allocated: 10000,
          spent: 10000,
          alerted: BudgetAlertLevel.warning,
        ),
      ]);

      expect(result.alerts.single.level, BudgetAlertLevel.exceeded);
      expect(result.alerts.single.percentUsed, 100);
      expect(result.levels, {1: BudgetAlertLevel.exceeded});
    });

    test('crossing both thresholds at once is one alert, at the higher', () {
      final result = _evaluate([_row(1, allocated: 10000, spent: 11000)]);

      expect(result.alerts, hasLength(1));
      expect(result.alerts.single.level, BudgetAlertLevel.exceeded);
      expect(result.alerts.single.percentUsed, 110);
    });

    test('a plan activated past a threshold announces it, since nothing '
        'has been yet', () {
      final result = _evaluate([
        _row(1, allocated: 10000, spent: 8500),
        _row(2, allocated: 5000, spent: 6000, name: 'Transport'),
        _row(3, allocated: 5000, spent: 100, name: 'Health'),
      ]);

      expect(result.alerts.map((a) => (a.allocationId, a.level)), [
        (1, BudgetAlertLevel.warning),
        (2, BudgetAlertLevel.exceeded),
      ]);
      expect(result.levels, {
        1: BudgetAlertLevel.warning,
        2: BudgetAlertLevel.exceeded,
      });
    });
  });

  group('no repeat', () {
    test('a row already announced at its level says nothing and stores '
        'nothing', () {
      final result = _evaluate([
        _row(
          1,
          allocated: 10000,
          spent: 9000,
          alerted: BudgetAlertLevel.warning,
        ),
        _row(
          2,
          allocated: 10000,
          spent: 25000,
          alerted: BudgetAlertLevel.exceeded,
        ),
      ]);

      expect(result.alerts, isEmpty);
      expect(result.isUnchanged, isTrue);
    });
  });

  group('downward', () {
    test('falling under a threshold stores the lower level and says '
        'nothing', () {
      final result = _evaluate([
        _row(
          1,
          allocated: 10000,
          spent: 9500,
          alerted: BudgetAlertLevel.exceeded,
        ),
        _row(
          2,
          allocated: 10000,
          spent: 1000,
          alerted: BudgetAlertLevel.warning,
        ),
      ]);

      expect(result.alerts, isEmpty);
      expect(result.levels, {
        1: BudgetAlertLevel.warning,
        2: BudgetAlertLevel.none,
      });
    });

    test('crossing again after falling is announced again', () {
      final fallen = _evaluate([
        _row(
          1,
          allocated: 10000,
          spent: 7000,
          alerted: BudgetAlertLevel.warning,
        ),
      ]);
      final again = _evaluate([
        _row(1, allocated: 10000, spent: 8000, alerted: fallen.levels[1]!),
      ]);

      expect(again.alerts.single.level, BudgetAlertLevel.warning);
    });
  });

  test('each change carries the level it was read from, for the store to '
      'compare against', () {
    final result = _evaluate([
      _row(
        1,
        allocated: 10000,
        spent: 10000,
        alerted: BudgetAlertLevel.warning,
      ),
      _row(2, allocated: 10000, spent: 0, alerted: BudgetAlertLevel.exceeded),
    ]);

    expect(result.changes, const [
      AlertLevelChange(
        allocationId: 1,
        from: BudgetAlertLevel.warning,
        to: BudgetAlertLevel.exceeded,
      ),
      AlertLevelChange(
        allocationId: 2,
        from: BudgetAlertLevel.exceeded,
        to: BudgetAlertLevel.none,
      ),
    ]);
  });

  group('rows it cannot speak for', () {
    test('an allocation never written has no id and is skipped', () {
      const unsaved = PlanAllocation(
        categoryId: 9,
        allocatedCents: 100,
        spentCents: 500,
        confidence: ConfidenceLevel.low,
      );

      final result = _evaluate([unsaved]);

      expect(result.alerts, isEmpty);
      expect(result.isUnchanged, isTrue);
    });

    test('a row read without its category name is still announced', () {
      final result = _evaluate([
        _row(1, allocated: 100, spent: 100, name: null),
      ]);

      expect(result.alerts.single.categoryName, 'A category');
    });
  });

  test('a seeded random walk of spend announces every upward crossing '
      'exactly once, and the stored level always ends where the spend is', () {
    final random = Random(20260924);
    const allocated = 10000;

    // The oracle states the thresholds directly rather than through the
    // code under test.
    int levelIndex(int spent) => spent >= allocated
        ? 2
        : spent * 100 >= allocated * 80
        ? 1
        : 0;

    for (var walk = 0; walk < 200; walk++) {
      var spent = 0;
      var stored = BudgetAlertLevel.none;
      var previous = 0;
      var expectedAlerts = 0;
      var alerts = 0;

      for (var step = 0; step < 60; step++) {
        // Mostly spending, sometimes an edit or delete taking some back.
        final delta = random.nextInt(10) < 7
            ? random.nextInt(1500)
            : -random.nextInt(2500);
        spent = max(0, spent + delta);

        final now = levelIndex(spent);
        if (now > previous) expectedAlerts++;
        previous = now;

        final result = _evaluate([
          _row(1, allocated: allocated, spent: spent, alerted: stored),
        ]);
        alerts += result.alerts.length;
        stored = result.levels[1] ?? stored;

        expect(stored.index, now, reason: 'walk $walk step $step');
        expect(
          _evaluate([
            _row(1, allocated: allocated, spent: spent, alerted: stored),
          ]).isUnchanged,
          isTrue,
          reason: 'a second evaluation of the same spend must be silent',
        );
      }

      expect(alerts, expectedAlerts, reason: 'walk $walk');
    }
  });
}
