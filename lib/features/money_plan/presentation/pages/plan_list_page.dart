import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/money_plan.dart';
import '../providers/money_plan_providers.dart';
import '../widgets/plan_labels.dart';

/// Every saved plan: which one is tracked, switching to another, and
/// picking two to compare. FR-PLN-015; the SDD's SCR-010.
///
/// The first screen to call `ActivatePlan` and `RecomputePlanSpending`.
/// Activation is the ordinary tap — it is reversible, the list shows the
/// switch through its stream at once, and the data layer recounts the
/// plan's spend as part of the same write — and the menu repeats it beside
/// the two rarer actions, so nothing here is only discoverable by tapping.
class PlanListPage extends ConsumerWidget {
  /// Creates the screen.
  const PlanListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved plans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.moneyPlan),
        icon: const Icon(Icons.add),
        label: const Text('Create Money Plan'),
      ),
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is Failure ? error.message : 'Could not read the plans.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (plans) =>
            plans.isEmpty ? const _NoPlans() : _PlanList(plans: plans),
      ),
    );
  }
}

class _PlanList extends ConsumerWidget {
  const _PlanList({required this.plans});

  final List<MoneyPlan> plans;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
    children: [
      for (final plan in plans)
        _PlanRow(
          plan: plan,
          onTap: plan.isActive
              ? () => context.push(Routes.activePlan)
              : () => _activate(context, ref, plan),
          onActivate: () => _activate(context, ref, plan),
          onRecount: () => _recount(context, ref, plan),
          onCompare: plans.length > 1
              ? () => _compare(context, plan, plans)
              : null,
        ),
    ],
  );

  Future<void> _activate(
    BuildContext context,
    WidgetRef ref,
    MoneyPlan plan,
  ) async {
    final written = await ref
        .read(activatePlanControllerProvider.notifier)
        .activate(plan.id!);
    if (!context.mounted) return;
    if (written) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${plan.name} is now active.')));
      return;
    }
    _showError(context, ref.read(activatePlanControllerProvider).error);
  }

  Future<void> _recount(
    BuildContext context,
    WidgetRef ref,
    MoneyPlan plan,
  ) async {
    final written = await ref
        .read(recomputePlanSpendingControllerProvider.notifier)
        .recount(plan.id!);
    if (!context.mounted) return;
    if (written) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${plan.name}\'s spending was recounted.')),
      );
      return;
    }
    _showError(
      context,
      ref.read(recomputePlanSpendingControllerProvider).error,
    );
  }

  Future<void> _compare(
    BuildContext context,
    MoneyPlan plan,
    List<MoneyPlan> plans,
  ) async {
    final others = [
      for (final p in plans)
        if (p.id != plan.id) p,
    ];
    final other = await showDialog<MoneyPlan>(
      context: context,
      builder: (_) => _PickPlanDialog(against: plan, options: others),
    );
    if (other == null || !context.mounted) return;
    await context.push(
      Uri(
        path: Routes.comparePlans,
        queryParameters: {'a': '${plan.id}', 'b': '${other.id}'},
      ).toString(),
    );
  }

  static void _showError(BuildContext context, Object? error) {
    if (error is Failure) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.plan,
    required this.onTap,
    required this.onActivate,
    required this.onRecount,
    required this.onCompare,
  });

  final MoneyPlan plan;
  final VoidCallback onTap;
  final VoidCallback onActivate;
  final VoidCallback onRecount;
  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = plan.period.days;
    return Card(
      child: ListTile(
        title: Row(
          children: [
            Expanded(child: Text(plan.name)),
            if (plan.isActive)
              Chip(
                label: const Text('Active'),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.primaryContainer,
              ),
          ],
        ),
        subtitle: Text(
          '${planPeriodLabel(plan.period)} · $days day${days == 1 ? '' : 's'}'
          ' · ${formatCents(plan.totalBudgetCents)}',
        ),
        trailing: PopupMenuButton<_PlanAction>(
          tooltip: 'More for ${plan.name}',
          onSelected: (action) => switch (action) {
            _PlanAction.activate => onActivate(),
            _PlanAction.recount => onRecount(),
            _PlanAction.compare => onCompare?.call(),
          },
          itemBuilder: (_) => [
            if (!plan.isActive)
              const PopupMenuItem(
                value: _PlanAction.activate,
                child: Text('Activate'),
              ),
            const PopupMenuItem(
              value: _PlanAction.recount,
              child: Text('Recount spending'),
            ),
            if (onCompare != null)
              const PopupMenuItem(
                value: _PlanAction.compare,
                child: Text('Compare with…'),
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

enum _PlanAction { activate, recount, compare }

/// Which plan to put beside [against]. Returns it, or null when dismissed.
class _PickPlanDialog extends StatefulWidget {
  const _PickPlanDialog({required this.against, required this.options});

  final MoneyPlan against;
  final List<MoneyPlan> options;

  @override
  State<_PickPlanDialog> createState() => _PickPlanDialogState();
}

class _PickPlanDialogState extends State<_PickPlanDialog> {
  late MoneyPlan _chosen = widget.options.first;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Compare ${widget.against.name} with'),
    content: DropdownButtonFormField<MoneyPlan>(
      initialValue: _chosen,
      items: [
        for (final p in widget.options)
          DropdownMenuItem(value: p, child: Text(p.name)),
      ],
      onChanged: (p) => setState(() => _chosen = p!),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_chosen),
        child: const Text('Compare'),
      ),
    ],
  );
}

/// E-22: say what belongs here and the one action that fills it.
class _NoPlans extends StatelessWidget {
  const _NoPlans();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No saved plans', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Every plan you save is kept here, so you can switch between '
              'them or compare two.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
