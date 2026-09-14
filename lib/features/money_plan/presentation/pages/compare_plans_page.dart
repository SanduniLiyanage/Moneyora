import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/money_plan.dart';
import '../../domain/entities/plan_comparison.dart';
import '../../domain/usecases/compare_plans.dart';
import '../providers/money_plan_providers.dart';
import '../widgets/plan_labels.dart';

/// Two saved plans side by side. FR-PLN-015.
///
/// Two columns, one per plan, a row per category either budgets, and
/// the difference under each pair — what the second plan gives the category
/// over the first. Nothing is scaled to a common period: the SRS's own
/// example puts a vacation plan beside a monthly one, and the reader wants
/// what each actually allots, with the periods on the header to read them
/// against.
class ComparePlansPage extends ConsumerWidget {
  /// Creates the screen for [request].
  const ComparePlansPage({required this.request, super.key});

  /// The two plans.
  final ComparePlansRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparison = ref.watch(planComparisonProvider(request));

    return Scaffold(
      appBar: AppBar(title: const Text('Compare plans')),
      body: comparison.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is Failure ? error.message : 'Could not compare the plans.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (comparison) => _Comparison(comparison: comparison),
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.comparison});

  final PlanComparison comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = comparison;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _PlanHeader(plan: c.left)),
            const SizedBox(width: 12),
            Expanded(child: _PlanHeader(plan: c.right)),
          ],
        ),
        const SizedBox(height: 16),
        _Line(
          label: 'Total',
          left: formatCents(c.left.totalBudgetCents),
          right: formatCents(c.right.totalBudgetCents),
          difference: c.totalDifferenceCents,
          bold: true,
        ),
        const Divider(),
        for (final row in c.rows)
          _Line(
            label: row.categoryName ?? 'Category ${row.categoryId}',
            left: row.left == null
                ? '—'
                : formatCents(row.left!.allocatedCents),
            right: row.right == null
                ? '—'
                : formatCents(row.right!.allocatedCents),
            difference: row.differenceCents,
          ),
        const SizedBox(height: 12),
        Text(
          'The difference is what the second plan gives the category over '
          'the first. A dash means the plan does not budget it.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.plan});

  final MoneyPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = plan.period.days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(plan.name, style: theme.textTheme.titleMedium),
        Text(
          '${planPeriodLabel(plan.period)} · $days day${days == 1 ? '' : 's'}'
          '${plan.isActive ? ' · active' : ''}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// One category, or the total: the label, the two figures, and under them
/// the difference in words.
class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.left,
    required this.right,
    required this.difference,
    this.bold = false,
  });

  final String label;
  final String left;
  final String right;
  final int difference;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bold
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          Row(
            children: [
              Expanded(child: Text(left, style: style)),
              const SizedBox(width: 12),
              Expanded(child: Text(right, style: style)),
            ],
          ),
          Text(differenceLabel(difference), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
