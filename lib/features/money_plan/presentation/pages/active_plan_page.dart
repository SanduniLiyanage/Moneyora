import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/money_plan.dart';
import '../../domain/entities/plan_allocation.dart';
import '../../domain/usecases/update_allocation.dart';
import '../../domain/usecases/what_if.dart';
import '../providers/money_plan_providers.dart';
import '../widgets/plan_labels.dart';

/// The active plan: what was saved, adjusted by hand, asked what-if.
/// FR-PLN-011, FR-PLN-012, FR-PLN-013.
///
/// Reached from the home screen as well as after a save, so it has to say
/// when there is no active plan and offer the way to make one (E-22).
/// Adjustment happens here, on the saved rows, where `UpdateAllocation`
/// holds the total; the recalculated rows arrive back through the live
/// stream, not through local state. Spend against the plan is FR-PLN-013's
/// slice and is not shown yet.
class ActivePlanPage extends ConsumerWidget {
  /// Creates the screen.
  const ActivePlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(activePlanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your plan'),
        actions: [
          if (plan.valueOrNull case final p? when p.allocations.length > 1)
            IconButton(
              tooltip: 'What if…',
              icon: const Icon(Icons.help_outline),
              onPressed: () => _showWhatIf(context, p),
            ),
        ],
      ),
      body: plan.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is Failure ? error.message : 'Could not read the plan.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (plan) =>
            plan == null ? const _NoActivePlan() : _Plan(plan: plan),
      ),
    );
  }

  Future<void> _showWhatIf(BuildContext context, MoneyPlan plan) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _WhatIfSheet(plan: plan),
        ),
      );
}

class _Plan extends ConsumerWidget {
  const _Plan({required this.plan});

  final MoneyPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final days = plan.period.days;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name, style: theme.textTheme.titleLarge),
                Text(
                  '${planPeriodLabel(plan.period)} · $days '
                  'day${days == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: theme.textTheme.titleMedium),
                    Text(
                      formatCents(plan.totalBudgetCents),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap a category to change its budget; the others adjust '
                  'to keep the total.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final allocation in plan.allocations)
          _AllocationRow(
            allocation: allocation,
            days: days,
            onTap: () => _adjust(context, ref, plan, allocation),
          ),
      ],
    );
  }

  Future<void> _adjust(
    BuildContext context,
    WidgetRef ref,
    MoneyPlan plan,
    PlanAllocation allocation,
  ) async {
    final cents = await showDialog<int>(
      context: context,
      builder: (_) => _AdjustDialog(allocation: allocation),
    );
    if (cents == null || !context.mounted) return;

    final written = await ref
        .read(updateAllocationControllerProvider.notifier)
        .adjust(
          UpdateAllocationRequest(
            planId: plan.id!,
            categoryId: allocation.categoryId,
            allocatedCents: cents,
          ),
        );
    if (written || !context.mounted) return;

    final error = ref.read(updateAllocationControllerProvider).error;
    if (error is Failure) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.allocation,
    required this.days,
    required this.onTap,
  });

  final PlanAllocation allocation;
  final int days;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = allocation;
    final perDay = days > 0 ? a.allocatedCents ~/ days : 0;
    final details = <String>[
      '${formatCents(perDay)} a day',
      if (a.expenseType case final type?) expenseTypeLabel(type),
      '${confidenceLabel(a.confidence)} confidence',
      if (a.isUserModified) 'set by you',
    ];
    return Card(
      child: ListTile(
        title: Text(a.categoryName ?? 'Category ${a.categoryId}'),
        subtitle: Text(details.join(' · ')),
        trailing: Text(
          formatCents(a.allocatedCents),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        onTap: onTap,
      ),
    );
  }
}

/// One allocation, set by hand. Returns the cents, or null when dismissed.
class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.allocation});

  final PlanAllocation allocation;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: formatCents(widget.allocation.allocatedCents, showSymbol: false),
  );
  String? _problem;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final cents = parseToCents(_amount.text);
    if (cents == null) {
      setState(() => _problem = 'Enter an amount.');
      return;
    }
    Navigator.of(context).pop(cents);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.allocation.categoryName ?? 'Allocation'),
    content: TextField(
      controller: _amount,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Budget for the period',
        prefixText: 'Rs ',
        errorText: _problem,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}

/// "If I reduce A by X%, how much more can go to B?" — answered, not
/// written. FR-PLN-012.
class _WhatIfSheet extends StatefulWidget {
  const _WhatIfSheet({required this.plan});

  final MoneyPlan plan;

  @override
  State<_WhatIfSheet> createState() => _WhatIfSheetState();
}

class _WhatIfSheetState extends State<_WhatIfSheet> {
  late int _from = widget.plan.allocations.first.categoryId;
  late int _to = widget.plan.allocations[1].categoryId;
  final TextEditingController _percent = TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();
    _percent.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  String _name(int categoryId) {
    final a = widget.plan.allocations.firstWhere(
      (a) => a.categoryId == categoryId,
    );
    return a.categoryName ?? 'Category ${a.categoryId}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = double.tryParse(_percent.text.trim());
    final valid = percent != null && percent >= 0 && percent <= 100;
    final result = valid
        ? WhatIf.reduce(
            widget.plan,
            fromCategoryId: _from,
            toCategoryId: _to,
            percent: percent,
          )
        : null;
    final items = [
      for (final a in widget.plan.allocations)
        DropdownMenuItem(value: a.categoryId, child: Text(_name(a.categoryId))),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What if…', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _from,
            decoration: const InputDecoration(labelText: 'Reduce'),
            items: items,
            onChanged: (v) => setState(() => _from = v!),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _percent,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'By',
              suffixText: '%',
              errorText: valid ? null : 'A percentage from 0 to 100.',
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _to,
            decoration: const InputDecoration(labelText: 'And give it to'),
            items: items,
            onChanged: (v) => setState(() => _to = v!),
          ),
          const SizedBox(height: 16),
          if (_from == _to)
            Text(
              'Pick two different categories.',
              style: theme.textTheme.bodyMedium,
            )
          else if (result != null) ...[
            Text(
              '${_name(_from)}: ${formatCents(result.reducedFromCents)} → '
              '${formatCents(result.reducedToCents)}',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              '${_name(_to)} could take ${formatCents(result.freedCents)} '
              'more: ${formatCents(result.raisedFromCents)} → '
              '${formatCents(result.raisedToCents)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'A preview: nothing changes until you set a category yourself.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// E-22: say what belongs here and the one action that fills it.
class _NoActivePlan extends StatelessWidget {
  const _NoActivePlan();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No active plan', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Build one from your spending, and it will be tracked here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push(Routes.moneyPlan),
              child: const Text('Create Money Plan'),
            ),
          ],
        ),
      ),
    );
  }
}
