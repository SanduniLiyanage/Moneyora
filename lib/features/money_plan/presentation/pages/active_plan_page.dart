import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/allocation_progress.dart';
import '../../domain/entities/money_plan.dart';
import '../../domain/entities/plan_allocation.dart';
import '../../domain/usecases/respond_to_overspend.dart';
import '../../domain/usecases/update_allocation.dart';
import '../../domain/usecases/what_if.dart';
import '../providers/money_plan_providers.dart';
import '../widgets/plan_labels.dart';

/// The active plan: what was saved, adjusted by hand, asked what-if,
/// tracked, and answered when a category runs over. FR-PLN-011, FR-PLN-012,
/// FR-PLN-013, FR-PLN-014.
///
/// Reached from the home screen as well as after a save, so it has to say
/// when there is no active plan and offer the way to make one (E-22).
/// Adjustment happens here, on the saved rows, where `UpdateAllocation`
/// holds the total; the recalculated rows arrive back through the live
/// stream, not through local state.
///
/// Tracking is display only. `PlanAllocation.spentCents` is kept by the
/// transactions datasource inside every expense write and re-read here
/// through the same stream, because the plan datasource shares the change
/// bus — so a row's bar moves the moment an expense is saved, with nothing
/// on this side but arithmetic: [AllocationProgress] over each row, the
/// period and [now].
///
/// A row spent past its allocation offers FR-PLN-014's three responses in
/// a sheet; each is `RespondToOverspend`'s, and a refusal is its sentence.
class ActivePlanPage extends ConsumerWidget {
  /// Creates the screen. [now] is the clock, injectable for tests.
  const ActivePlanPage({super.key, this.now});

  /// The clock. `DateTime.now()` when null.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(activePlanProvider);
    final today = now ?? DateTime.now();

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
        data: (plan) => plan == null
            ? const _NoActivePlan()
            : _Plan(plan: plan, today: today),
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
  const _Plan({required this.plan, required this.today});

  final MoneyPlan plan;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final days = plan.period.days;
    final progress = [
      for (final a in plan.allocations)
        AllocationProgress.of(a, plan.period, today),
    ];
    final spent = plan.allocations.fold(0, (s, a) => s + a.spentCents);
    final elapsed = progress.isEmpty ? 0 : progress.first.elapsedDays;

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
                Text(
                  '${formatCents(spent)} spent · '
                  '${_dayLabel(elapsed, days)}',
                  style: theme.textTheme.bodyMedium,
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
        for (final p in progress)
          _AllocationRow(
            progress: p,
            days: days,
            onTap: () => _adjust(context, ref, plan, p.allocation),
            onRespond: p.allocation.overspendCents > 0
                ? () => _respond(context, ref, plan, p.allocation)
                : null,
          ),
      ],
    );
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    MoneyPlan plan,
    PlanAllocation allocation,
  ) async {
    final response = await showModalBottomSheet<OverspendResponse>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OverspendSheet(plan: plan, allocation: allocation),
    );
    if (response == null || !context.mounted) return;

    final written = await ref
        .read(respondToOverspendControllerProvider.notifier)
        .respond(
          OverspendRequest(
            planId: plan.id!,
            categoryId: allocation.categoryId,
            response: response,
          ),
        );
    if (written || !context.mounted) return;

    final error = ref.read(respondToOverspendControllerProvider).error;
    if (error is Failure) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  static String _dayLabel(int elapsed, int days) =>
      elapsed == 0 ? 'not started' : 'day $elapsed of $days';

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

/// One category: its budget, its provenance, and FR-PLN-013's three
/// figures beneath — the bar in the status colour, the percentage and
/// the projection.
class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.progress,
    required this.days,
    required this.onTap,
    this.onRespond,
  });

  final AllocationProgress progress;
  final int days;
  final VoidCallback onTap;

  /// Opens FR-PLN-014's responses; null when the row is within budget.
  final VoidCallback? onRespond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = progress.allocation;
    final perDay = days > 0 ? a.allocatedCents ~/ days : 0;
    final details = <String>[
      '${formatCents(perDay)} a day',
      if (a.expenseType case final type?) expenseTypeLabel(type),
      '${confidenceLabel(a.confidence)} confidence',
      if (a.isUserModified) 'set by you',
    ];
    final colour = trackingColour(theme, progress.status);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(a.categoryName ?? 'Category ${a.categoryId}'),
              subtitle: Text(details.join(' · ')),
              trailing: Text(
                formatCents(a.allocatedCents),
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    // The bar fills at 100% and stays full past it; the
                    // number beside it is what says how far past.
                    value: (progress.percentUsed / 100).clamp(0, 1),
                    color: colour,
                    backgroundColor: colour.withValues(alpha: 0.2),
                    minHeight: 6,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    trackingLabel(progress),
                    style: theme.textTheme.bodySmall?.copyWith(color: colour),
                  ),
                  if (a.carryOverCents > 0)
                    Text(
                      '${formatCents(a.carryOverCents)} carried to your '
                      'next plan',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (onRespond case final respond?)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: respond,
                        child: Text(
                          'Over by ${formatCents(a.overspendCents)} · '
                          'Respond',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// FR-PLN-014's three responses, chosen and returned; nothing written here.
class _OverspendSheet extends StatefulWidget {
  const _OverspendSheet({required this.plan, required this.allocation});

  final MoneyPlan plan;
  final PlanAllocation allocation;

  @override
  State<_OverspendSheet> createState() => _OverspendSheetState();
}

class _OverspendSheetState extends State<_OverspendSheet> {
  int? _from;

  String _name(PlanAllocation a) =>
      a.categoryName ?? 'Category ${a.categoryId}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.allocation;
    final over = formatCents(a.overspendCents);
    final others = [
      for (final o in widget.plan.allocations)
        if (o.categoryId != a.categoryId) o,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_name(a)} is over by $over',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-redistribute'),
            subtitle: Text(
              'Raise ${_name(a)} to ${formatCents(a.spentCents)} and take '
              '$over from the other categories, in proportion to what each '
              'has left.',
            ),
            onTap: () =>
                Navigator.of(context)
                    .pop(const OverspendResponse.autoRedistribute()),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Manual adjust'),
            subtitle: Text('Take $over from one category you choose.'),
            onTap: () => setState(() => _from = others.first.categoryId),
          ),
          if (_from case final from?) ...[
            DropdownButtonFormField<int>(
              initialValue: from,
              decoration: const InputDecoration(labelText: 'Reduce'),
              items: [
                for (final o in others)
                  DropdownMenuItem(
                    value: o.categoryId,
                    child: Text(
                      '${_name(o)} · ${formatCents(o.remainingCents)} left',
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _from = v),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context)
                    .pop(OverspendResponse.manualAdjust(fromCategoryId: from)),
                child: const Text('Apply'),
              ),
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Carry over'),
            subtitle: Text(
              'Leave this plan as it is and deduct $over from ${_name(a)} in '
              'your next plan.',
            ),
            onTap: () =>
                Navigator.of(context).pop(const OverspendResponse.carryOver()),
          ),
        ],
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
