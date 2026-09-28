import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/scale_down_text.dart';
import '../../../../injection.dart' show notificationSettingsProvider;
import '../../domain/entities/allocation_request.dart';
import '../../domain/entities/category_allocation.dart';
import '../../domain/entities/confidence_score.dart';
import '../../domain/entities/lookback_window.dart';
import '../../domain/entities/money_plan_draft.dart';
import '../../domain/entities/plan_line.dart';
import '../../domain/usecases/save_plan.dart';
import '../providers/money_plan_providers.dart';
import '../widgets/plan_labels.dart';
import '../widgets/plan_name_dialog.dart';
import 'plan_editor_page.dart';

/// The generated draft, for review. FR-PLN-007, FR-PLN-009, FR-PLN-010.
///
/// Shows every figure with its provenance — the monthly base, the seasonal
/// and trend factors, the class, the confidence and the reason for it —
/// because a budget the user cannot interrogate is a budget they will not
/// trust (E-07). Save names the plan and activates it. Edit amounts opens
/// the plan editor with these figures, to change them before saving
/// (FR-PLN-011, E-39); what-if (FR-PLN-012) and the total-holding adjust
/// happen on the *saved* plan.
class PlanReviewPage extends ConsumerWidget {
  /// Creates the review screen for [request].
  const PlanReviewPage({required this.request, super.key});

  /// What the wizard's first step asked for.
  final AllocationRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(planDraftProvider(request));
    final saving = ref.watch(savePlanControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Your plan')),
      body: draft.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Problem(error: error),
        data: (draft) => draft.isEmpty
            ? _NothingToPlanFrom(request: request)
            : _Draft(draft: draft),
      ),
      bottomNavigationBar: switch (draft.valueOrNull) {
        final MoneyPlanDraft d when !d.isEmpty => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: saving ? null : () => _edit(context, d),
                    child: const Text('Edit amounts'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: saving ? null : () => _save(context, ref, d),
                    child: Text(saving ? 'Saving…' : 'Save plan'),
                  ),
                ),
              ],
            ),
          ),
        ),
        _ => null,
      },
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    MoneyPlanDraft draft,
  ) async {
    final choice = await PlanNameDialog.show(
      context,
      offerAlerts:
          ref
              .read(notificationSettingsProvider)
              .valueOrNull
              ?.budgetAlertsEnabled ==
          false,
      initial: planPeriodLabel(draft.period),
    );
    if (choice == null || !context.mounted) return;

    final id = await ref
        .read(savePlanControllerProvider.notifier)
        .save(
          SavePlanRequest(
            draft: draft,
            name: choice.name,
            activate: choice.activate,
          ),
        );
    if (!context.mounted) return;

    if (id != null) {
      final messenger = ScaffoldMessenger.of(context);
      final alerts = await PlanNameDialog.alertsFor(ref, choice);
      if (!context.mounted) return;
      // Home underneath, the saved plan on top: back leaves to home, not to
      // a review of a draft that has already been saved. A plan saved for
      // later (FR-PLN-015) lands on the list, where it can be activated.
      context.go(Routes.home);
      unawaited(
        context.push(choice.activate ? Routes.activePlan : Routes.plans),
      );
      if (alerts != null) unawaited(PlanNameDialog.turnOn(alerts, messenger));
      return;
    }

    final error = ref.read(savePlanControllerProvider).error;
    if (error is Failure) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// Opens the plan editor on [draft]'s figures. FR-PLN-011, E-39.
void _edit(BuildContext context, MoneyPlanDraft draft) => unawaited(
  context.push(
    Routes.planEditor,
    extra: PlanEditorArgs(
      period: draft.period,
      lines: [for (final a in draft.allocations) PlanLine.suggested(a)],
      suggestedTotalCents: draft.totalCents,
    ),
  ),
);

class _Draft extends StatelessWidget {
  const _Draft({required this.draft});

  final MoneyPlanDraft draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  planPeriodLabel(draft.period),
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${draft.period.days} day${draft.period.days == 1 ? '' : 's'}'
                  ' · ${budgetModeLabel(draft.mode)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _Figure(label: 'Total', cents: draft.totalCents, bold: true),
                if (draft.incomeCents case final income?)
                  _Figure(label: 'Income', cents: income),
                if (draft.savingsTargetCents case final savings?)
                  _Figure(label: 'Savings', cents: savings),
                if (draft.unallocatedCents case final left? when left > 0)
                  _Figure(label: 'Unallocated', cents: left),
                if (draft.carriedFromPlan case final from?)
                  _Figure(
                    label: 'Carried over from $from',
                    cents: -draft.carryOverCents,
                  ),
                const SizedBox(height: 4),
                Text(
                  'From the last ${draft.lookback.months} months.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final allocation in draft.allocations)
          _AllocationCard(allocation: allocation),
        const SizedBox(height: 8),
        _PatternsCard(
          lookback: draft.lookback,
          names: {
            for (final a in draft.allocations)
              a.classification.categoryId: a.classification.statistics.name,
          },
        ),
      ],
    );
  }
}

/// When in the week and the month the money goes. FR-PLN-006.
///
/// Over the same months as the figures above it, so a habit named here is
/// one those figures learned from.
class _PatternsCard extends ConsumerWidget {
  const _PatternsCard({required this.lookback, required this.names});

  final LookbackWindow lookback;

  /// Category names by id, to say which were left out as bills.
  final Map<int, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lines = switch (ref.watch(spendingPatternsProvider(lookback))) {
      AsyncData(:final value) => spendingPatternLines(
        value,
        leftOut: [for (final id in value.leftOut) ?names[id]],
      ),
      AsyncError(:final error) => [
        error is Failure
            ? error.message
            : 'Your spending patterns could not be read.',
      ],
      _ => null,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spending patterns', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (lines == null)
              const LinearProgressIndicator()
            else
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(line, style: theme.textTheme.bodyMedium),
                ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.cents, this.bold = false});

  final String label;
  final int cents;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 8),
        ScaleDownText(formatCents(cents), style: style),
      ],
    );
  }
}

/// One category: the figure, and how it was reached.
class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.allocation});

  final CategoryAllocation allocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = allocation;
    final factors = <String>[
      '${formatCents(a.baseMonthlyCents)} a month',
      if (a.seasonalFactor != 1.0)
        '×${a.seasonalFactor.toStringAsFixed(2)} seasonal',
      if (a.trendFactor != 1.0)
        '×${a.trendFactor.toStringAsFixed(2)} '
            '${a.trendFactor > 1 ? 'rising' : 'falling'}',
      // FR-PLN-014: what last plan's overspend took off this one.
      if (a.carryOverCents > 0)
        '−${formatCents(a.carryOverCents)} carried over',
    ];
    final seasonal = a.classification.seasonalMonths;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(a.name, style: theme.textTheme.titleMedium),
                ),
                const SizedBox(width: 8),
                ScaleDownText(
                  formatCents(a.allocationCents),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            Text(
              '${formatCents(a.dailyAllowanceCents)} a day',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _Tag(expenseTypeLabel(a.type)),
                _Tag(
                  '${confidenceLabel(a.confidence.level)} confidence',
                  emphasis: a.confidence.level,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(factors.join(' · '), style: theme.textTheme.bodySmall),
            if (seasonal.isNotEmpty)
              Text(
                'Spikes every ${seasonal.map(monthAbbreviation).join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            Text(
              confidenceReason(a.confidence),
              style: theme.textTheme.bodySmall?.copyWith(
                color: a.confidence.isCappedByLookback
                    ? theme.colorScheme.error
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.emphasis});

  final String text;
  final ConfidenceLevel? emphasis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = switch (emphasis) {
      ConfidenceLevel.low => scheme.errorContainer,
      ConfidenceLevel.high => scheme.primaryContainer,
      _ => scheme.surfaceContainerHighest,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// E-21, E-22, E-39: nothing in the lookback to suggest a plan from. The
/// way on is a plan the user builds, not an empty screen.
class _NothingToPlanFrom extends StatelessWidget {
  const _NothingToPlanFrom({required this.request});

  /// What the wizard asked for: its period is the plan's.
  final AllocationRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = request.lookback.months;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insights_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Not enough history to suggest a plan',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'There is no spending in the last '
              '${months == 1 ? 'month' : '$months months'} to learn from. '
              'You can build this plan yourself, and Moneyora will suggest '
              'one once it knows how you spend.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => unawaited(
                context.push(
                  Routes.planEditor,
                  extra: PlanEditorArgs(period: request.period),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Build it yourself'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The use case's own refusal, or a failure beneath it, in its own words.
class _Problem extends StatelessWidget {
  const _Problem({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error) {
      final Failure f => f.message,
      _ => 'Could not build the plan.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
