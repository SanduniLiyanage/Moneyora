import '../../../../core/utils/date_utils.dart';
import '../../domain/entities/money_plan.dart';
import '../../domain/entities/plan_period.dart';
import 'plan_allocation_model.dart';

/// Persistence mapping for [MoneyPlan]. FR-PLN-001, FR-PLN-015.
///
/// `created_at` and `user_id` are bookkeeping and live here, not on the
/// entity, as `AccountModel` does it. The period's shape is stored as
/// `period_type`, whose check constraint lists [PlanPeriodType] in snake
/// case.
class MoneyPlanModel extends MoneyPlan {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const MoneyPlanModel({
    required super.name,
    required super.period,
    required super.totalBudgetCents,
    required List<PlanAllocationModel> super.allocations,
    super.id,
    super.isActive,
    this.userId = 1,
    this.createdAt,
  });

  /// Wraps an entity so it can be written.
  factory MoneyPlanModel.fromEntity(
    MoneyPlan plan, {
    int userId = 1,
    DateTime? createdAt,
  }) => MoneyPlanModel(
    id: plan.id,
    name: plan.name,
    period: plan.period,
    totalBudgetCents: plan.totalBudgetCents,
    isActive: plan.isActive,
    allocations: [
      for (final a in plan.allocations) PlanAllocationModel.fromEntity(a),
    ],
    userId: userId,
    createdAt: createdAt,
  );

  /// Rebuilds a model from a `money_plans` row and its allocation rows.
  factory MoneyPlanModel.fromMap(
    Map<String, Object?> map,
    List<Map<String, Object?>> allocationRows,
  ) => MoneyPlanModel(
    id: map['id'] as int?,
    name: map['name']! as String,
    period: PlanPeriod(
      from: decodeIsoDay(map['start_date']! as String),
      to: decodeIsoDay(map['end_date']! as String),
      type: decodePeriodType(map['period_type']! as String),
    ),
    totalBudgetCents: map['total_budget_cents']! as int,
    isActive: map['is_active'] == 1,
    allocations: allocationRows.map(PlanAllocationModel.fromMap).toList(),
    userId: map['user_id'] as int? ?? 1,
    createdAt: switch (map['created_at']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
  );

  /// Owner, always 1 until multi-user exists.
  final int userId;

  /// When the row was written.
  final DateTime? createdAt;

  /// The allocations, typed as models.
  List<PlanAllocationModel> get allocationModels =>
      allocations.cast<PlanAllocationModel>();

  /// The `money_plans` row.
  Map<String, Object?> toMap({required DateTime now}) => {
    'user_id': userId,
    'name': name,
    'period_type': encodePeriodType(period.type),
    'start_date': encodeIsoDay(period.from),
    'end_date': encodeIsoDay(period.to),
    'total_budget_cents': totalBudgetCents,
    'is_active': isActive ? 1 : 0,
    'created_at': (createdAt ?? now).toIso8601String(),
  };

  /// `period_type`'s stored form.
  static String encodePeriodType(PlanPeriodType type) => switch (type) {
    PlanPeriodType.day => 'day',
    PlanPeriodType.week => 'week',
    PlanPeriodType.month => 'month',
    PlanPeriodType.year => 'year',
    PlanPeriodType.customDays => 'custom_days',
    PlanPeriodType.customRange => 'custom_range',
  };

  /// [PlanPeriodType] from its stored form.
  static PlanPeriodType decodePeriodType(String value) => switch (value) {
    'day' => PlanPeriodType.day,
    'week' => PlanPeriodType.week,
    'month' => PlanPeriodType.month,
    'year' => PlanPeriodType.year,
    'custom_days' => PlanPeriodType.customDays,
    'custom_range' => PlanPeriodType.customRange,
    _ => throw FormatException('Unknown period_type', value),
  };

  /// Converts back at the repository boundary.
  MoneyPlan toEntity() => MoneyPlan(
    id: id,
    name: name,
    period: period,
    totalBudgetCents: totalBudgetCents,
    isActive: isActive,
    allocations: [for (final a in allocationModels) a.toEntity()],
  );
}
