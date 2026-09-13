import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/allocation_request.dart';
import '../../domain/entities/category_allocation.dart';
import '../../domain/entities/confidence_score.dart';
import '../../domain/entities/money_plan_draft.dart';
import '../providers/money_plan_providers.dart';
import '../widgets/plan_labels.dart';

/// The generated draft, for review. FR-PLN-007, FR-PLN-009, FR-PLN-010.
///
/// Shows every figure with its provenance — the monthly base, the seasonal
/// and trend factors, the class, the confidence and the reason for it —
/// because a budget the user cannot interrogate is a budget they will not
/// trust (E-07). Nothing is saved from here yet; saving, adjusting
/// (FR-PLN-011) and what-if (FR-PLN-012) are the next slice, and adjusting
/// happens on the *saved* plan, where `UpdateAllocation` already holds the
/// total.
class PlanReviewPage extends ConsumerWidget {
  /// Creates the review screen for [request].
  const PlanReviewPage({required this.request, super.key});

  /// What the wizard's first step asked for.
  final AllocationRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(planDraftProvider(request));

    return Scaffold(
      appBar: AppBar(title: const Text('Your plan')),
      body: draft.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Problem(error: error),
        data: (draft) =>
            draft.isEmpty ? const _NothingToPlanFrom() : _Draft(draft: draft),
      ),
    );
  }
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
      ],
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(formatCents(cents), style: style),
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
                Text(
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
class _NothingToPlanFrom extends StatelessWidget {
  const _NothingToPlanFrom();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
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
