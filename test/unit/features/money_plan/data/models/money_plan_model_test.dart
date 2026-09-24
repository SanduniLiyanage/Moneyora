import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/money_plan/data/models/money_plan_model.dart';
import 'package:moneyora/features/money_plan/data/models/plan_allocation_model.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_level.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';

void main() {
  group('the stored strings', () {
    // What `v1_initial.dart`'s check constraints list — lowercase, unlike
    // the DBD's capitalised spellings.
    test('confidence_level', () {
      expect(
        PlanAllocationModel.encodeConfidence(ConfidenceLevel.high),
        'high',
      );
      expect(
        PlanAllocationModel.encodeConfidence(ConfidenceLevel.medium),
        'medium',
      );
      expect(PlanAllocationModel.encodeConfidence(ConfidenceLevel.low), 'low');
      for (final level in ConfidenceLevel.values) {
        expect(
          PlanAllocationModel.decodeConfidence(
            PlanAllocationModel.encodeConfidence(level),
          ),
          level,
        );
      }
    });

    test('expense_class', () {
      expect(PlanAllocationModel.encodeExpenseType(ExpenseType.fixed), 'fixed');
      expect(
        PlanAllocationModel.encodeExpenseType(ExpenseType.variable),
        'variable',
      );
      expect(
        PlanAllocationModel.encodeExpenseType(ExpenseType.seasonal),
        'seasonal',
      );
      for (final type in ExpenseType.values) {
        expect(
          PlanAllocationModel.decodeExpenseType(
            PlanAllocationModel.encodeExpenseType(type),
          ),
          type,
        );
      }
    });

    test('period_type', () {
      expect(MoneyPlanModel.encodePeriodType(PlanPeriodType.day), 'day');
      expect(MoneyPlanModel.encodePeriodType(PlanPeriodType.week), 'week');
      expect(MoneyPlanModel.encodePeriodType(PlanPeriodType.month), 'month');
      expect(MoneyPlanModel.encodePeriodType(PlanPeriodType.year), 'year');
      expect(
        MoneyPlanModel.encodePeriodType(PlanPeriodType.customDays),
        'custom_days',
      );
      expect(
        MoneyPlanModel.encodePeriodType(PlanPeriodType.customRange),
        'custom_range',
      );
      for (final type in PlanPeriodType.values) {
        expect(
          MoneyPlanModel.decodePeriodType(
            MoneyPlanModel.encodePeriodType(type),
          ),
          type,
        );
      }
      expect(
        () => MoneyPlanModel.decodePeriodType('fortnight'),
        throwsFormatException,
      );
    });

    // E-35: the percentage each level names, as `v5_budget_alerts.dart`'s
    // CHECK lists them.
    test('alerted_level', () {
      expect(PlanAllocationModel.encodeAlertLevel(BudgetAlertLevel.none), 0);
      expect(
        PlanAllocationModel.encodeAlertLevel(BudgetAlertLevel.warning),
        80,
      );
      expect(
        PlanAllocationModel.encodeAlertLevel(BudgetAlertLevel.exceeded),
        100,
      );
      for (final level in BudgetAlertLevel.values) {
        expect(
          PlanAllocationModel.decodeAlertLevel(
            PlanAllocationModel.encodeAlertLevel(level),
          ),
          level,
        );
      }
      expect(
        () => PlanAllocationModel.decodeAlertLevel(50),
        throwsFormatException,
      );
    });
  });

  group('round trips', () {
    final plan = MoneyPlan(
      id: 3,
      name: 'September',
      period: PlanPeriod.month(2026, 9),
      totalBudgetCents: 7500000,
      isActive: true,
      allocations: const [
        PlanAllocation(
          id: 10,
          categoryId: 1,
          categoryName: 'Bills',
          allocatedCents: 4500000,
          confidence: ConfidenceLevel.high,
          expenseType: ExpenseType.fixed,
        ),
        PlanAllocation(
          id: 11,
          categoryId: 2,
          categoryName: 'Food',
          allocatedCents: 3000000,
          spentCents: 120000,
          carryOverCents: 25000,
          confidence: ConfidenceLevel.medium,
          isUserModified: true,
          notes: 'trimmed',
          alertedLevel: BudgetAlertLevel.warning,
        ),
      ],
    );

    test('a plan row and its allocation rows rebuild the entity', () {
      final model = MoneyPlanModel.fromEntity(plan);
      final row = model.toMap(now: DateTime(2026, 9, 13));
      final rows = [for (final a in model.allocationModels) a.toMap(3)];

      expect(row['period_type'], 'month');
      expect(row['start_date'], '2026-09-01');
      expect(row['end_date'], '2026-09-30');
      expect(row['total_budget_cents'], 7500000);
      expect(row['is_active'], 1);
      expect(rows[0]['plan_id'], 3);
      expect(rows[0]['confidence_level'], 'high');
      expect(rows[0]['expense_class'], 'fixed');
      expect(rows[1]['expense_class'], isNull);
      expect(rows[1]['is_user_modified'], 1);
      expect(rows[1]['carry_over_cents'], 25000);
      expect(rows[0]['alerted_level'], 0);
      expect(rows[1]['alerted_level'], 80);

      // Read back as SQLite would hand them, with the ids and the joined
      // category name the query adds.
      final rebuilt = MoneyPlanModel.fromMap(
        {...row, 'id': 3},
        [
          {...rows[0], 'id': 10, 'category_name': 'Bills'},
          {...rows[1], 'id': 11, 'category_name': 'Food'},
        ],
      ).toEntity();

      expect(rebuilt, plan);
    });

    test('toEntity is an entity, not a model, so equality holds', () {
      final model = MoneyPlanModel.fromEntity(plan);

      expect(model, isNot(plan));
      expect(model.toEntity(), plan);
    });
  });
}
