import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/ports/category_reader.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../injection.dart';
import '../../domain/entities/recurring_rule.dart';
import '../../domain/entities/transaction.dart';
import '../providers/recurring_providers.dart';
import '../providers/transaction_providers.dart';
import '../widgets/recurrence_labels.dart';

/// Every recurring rule, active and stopped. FR-EXP-008, FR-INC-004.
///
/// The SDD's screen inventory has no screen for this (E-13's addendum): the
/// entry screen's toggle creates a rule and nothing else can see one. Each
/// row says what repeats — the template's category and amount — how often,
/// and where it stands; a tap opens the rule with Pause or Resume and
/// Delete. Reached from the home screen's list as "Recurring".
class RecurringRulesPage extends ConsumerWidget {
  /// Creates the rules list.
  const RecurringRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider);
    // Names only; a list without them still says what repeats by amount.
    final categories = {
      for (final c
          in ref.watch(entryCategoriesProvider).valueOrNull ??
              const <CategoryOption>[])
        c.id: c.name,
    };
    final today = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              failureMessage(error) ?? 'Could not load your repeats.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (series) => series.isEmpty
            ? const _Empty()
            : ListView.separated(
                itemCount: series.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _RuleRow(
                  series: series[i],
                  name: _nameOf(series[i], categories),
                  today: today,
                ),
              ),
      ),
    );
  }
}

/// What a series is called on the list: its category, else its note.
String _nameOf(RecurringSeries series, Map<int, String> categories) {
  final template = series.template;
  if (template == null) return 'Deleted entry';
  return categories[template.categoryId] ?? template.note ?? 'Repeat';
}

/// E-22: what belongs here, and the one action that fills it.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No repeating entries yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap Repeat, top right of the entry screen, when you add an '
              'expense or income that comes round again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.series,
    required this.name,
    required this.today,
  });

  final RecurringSeries series;
  final String name;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final rule = series.rule;
    final template = series.template;
    final status = rule.statusOn(today);
    final running =
        status == RecurrenceStatus.active || status == RecurrenceStatus.overdue;

    return ListTile(
      leading: Icon(
        running ? Icons.repeat : Icons.pause_circle_outline,
        color: running ? null : Theme.of(context).disabledColor,
      ),
      title: Text(name),
      subtitle: Text(
        '${describeRecurrence(rule)}\n${describeStatus(rule, today)}',
      ),
      isThreeLine: true,
      trailing: template == null ? null : _Amount(template),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _RuleSheet(series: series, name: name, today: today),
      ),
    );
  }
}

/// The amount in the colour of what it is: money out or money in.
class _Amount extends StatelessWidget {
  const _Amount(this.template);

  final Transaction template;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final expense = template.type == TransactionType.expense;
    return Text(
      formatCents(template.amountCents),
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: expense ? colors.expense : colors.income),
    );
  }
}

/// One rule, and what can be done with it.
///
/// Pause on a rule that posts, Resume on a paused one, Delete on any. An
/// ended rule, or one whose template is gone, can only be deleted: neither
/// has anything left to post (E-36).
class _RuleSheet extends ConsumerWidget {
  const _RuleSheet({
    required this.series,
    required this.name,
    required this.today,
  });

  final RecurringSeries series;
  final String name;
  final DateTime today;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<bool> Function(RecurringRuleActionsController) action,
  ) async {
    final done = await action(ref.read(recurringRuleActionsProvider.notifier));
    if (done && context.mounted) Navigator.of(context).pop();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this repeat?'),
        content: const Text(
          'Nothing more will be added. The entries it already added stay in '
          'your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _act(context, ref, (c) => c.delete(series.rule));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rule = series.rule;
    final status = rule.statusOn(today);
    final action = ref.watch(recurringRuleActionsProvider);
    final busy = action.isLoading;
    final message = failureMessage(action.error);
    final date = DateFormat.yMMMd();
    final end = rule.endDate;
    final last = rule.lastCreatedAt;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(describeRecurrence(rule), style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            Text('Started ${date.format(rule.startDate)}'),
            Text(end == null ? 'No end date' : 'Ends ${date.format(end)}'),
            if (last != null) Text('Last added ${date.format(last)}'),
            const SizedBox(height: 8),
            Text(
              describeStatus(rule, today),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  message,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: busy ? null : () => _delete(context, ref),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Delete'),
                ),
                const Spacer(),
                if (status == RecurrenceStatus.active ||
                    status == RecurrenceStatus.overdue)
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _act(context, ref, (c) => c.pause(rule)),
                    child: const Text('Pause'),
                  ),
                if (status == RecurrenceStatus.paused)
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => _act(context, ref, (c) => c.resume(rule)),
                    child: const Text('Resume'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
