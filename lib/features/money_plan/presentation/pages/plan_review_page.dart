import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/scale_down_text.dart';
import '../../domain/entities/allocation_request.dart';
import '../../domain/entities/category_allocation.dart';
import '../../domain/entities/confidence_score.dart';
import '../../domain/entities/lookback_window.dart';
import '../../domain/entities/money_plan_draft.dart';
import '../../domain/usecases/save_plan.dart';
import '../providers/money_plan_providers.dart';
import '../widgets/plan_labels.dart';

/// The generated draft, for review. FR-PLN-007, FR-PLN-009, FR-PLN-010.
///
/// Shows every figure with its provenance — the monthly base, the seasonal
/// and trend factors, the class, the confidence and the reason for it —
/// because a budget the user cannot interrogate is a budget they will not
/// trust (E-07). Save names the plan and activates it; adjusting
/// (FR-PLN-011) and what-if (FR-PLN-012) happen on the *saved* plan, where
/// `UpdateAllocation` already holds the total — so a save lands there.
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
            child: FilledButton(
              onPressed: saving ? null : () => _save(context, ref, d),
              child: Text(saving ? 'Saving…' : 'Save plan'),
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
    final choice = await showDialog<({String name, bool activate})>(
      context: context,
      builder: (_) => _NameDialog(initial: planPeriodLabel(draft.period)),
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
      // Home underneath, the saved plan on top: back leaves to home, not to
      // a review of a draft that has already been saved. A plan saved for
      // later (FR-PLN-015) lands on the list, where it can be activated.
      context.go(Routes.home);
      unawaited(
        context.push(choice.activate ? Routes.activePlan : Routes.plans),
      );
      return;
    }

    final error = ref.read(savePlanControllerProvider).error;
    if (error is Failure) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// Asks what to call the plan and whether to track it now. Returns both,
/// or null when dismissed. Saving without activating is FR-PLN-015's "June
/// Vacation Plan" kept beside the "Regular Monthly" still being tracked.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );
  bool _activate = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop((name: _name.text, activate: _activate));

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Name your plan'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => _submit(),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _activate,
          onChanged: (v) => setState(() => _activate = v ?? true),
          title: const Text('Track it now'),
          subtitle: const Text('Untick to keep it for later.'),
        ),
      ],
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
        _PatternsCard(lookback: draft.lookback),
      ],
    );
  }
}

/// When in the week and the month the money goes. FR-PLN-006.
///
/// Over the same months as the figures above it, so a habit named here is
/// one those figures learned from.
class _PatternsCard extends ConsumerWidget {
  const _PatternsCard({required this.lookback});

  final LookbackWindow lookback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lines = switch (ref.watch(spendingPatternsProvider(lookback))) {
      AsyncData(:final value) => spendingPatternLines(value),
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

/// E-21 / E-22: a plan needs history, and a first-time user has none.
class _NothingToPlanFrom extends ConsumerWidget {
  const _NothingToPlanFrom({required this.request});

  /// The request to generate again once there is history.
  final AllocationRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final loading = ref.watch(devSeedLoaderProvider).isLoading;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nothing to plan from yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'A plan is built from your spending. Add some expenses, and '
              'this will fill in.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            // Debug builds only, and stripped from release by the constant:
            // two years of shaped history is what lets the generator be
            // tried by eye on a phone with none.
            if (kDebugMode) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: loading
                    ? null
                    : () => _loadSampleData(context, ref, request),
                icon: loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.science_outlined),
                label: const Text('Try it with sample data'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks, loads the sample history once, says what happened, and plans
/// again from it. Debug builds only.
Future<void> _loadSampleData(
  BuildContext context,
  WidgetRef ref,
  AllocationRequest request,
) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Load sample data?'),
      content: const Text(
        'Adds two years of made-up transactions — rent, groceries, gifts, '
        'fuel, a pet, a salary — to this phone, so a plan has history to '
        'learn from. It is added once; Settings › Clear all data removes '
        'it. Debug builds only.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Load'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final result = await ref.read(devSeedLoaderProvider.notifier).load();
  if (!context.mounted) return;
  final error = ref.read(devSeedLoaderProvider).error;
  final message = switch (result) {
    null =>
      'Could not load the sample data: '
          '${error is Failure ? error.message : 'please try again.'}',
    SampleDataLoad(alreadyLoaded: true) =>
      'The sample data is already loaded. Clear all data in Settings to '
          'start again.',
    SampleDataLoad(:final written) => 'Added $written sample transactions.',
  };
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
  // The draft was generated from no history; generate it again from this.
  if (result != null) ref.invalidate(planDraftProvider(request));
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
