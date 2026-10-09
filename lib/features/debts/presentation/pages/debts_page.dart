import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/scale_down_text.dart';
import '../../../../injection.dart' show clockProvider;
import '../../domain/entities/debt.dart';
import '../../domain/entities/debt_totals.dart';
import '../providers/debt_providers.dart';

/// Money owed, either way, and what is still open. FR-DBT-002, E-42.
///
/// What is owed to the user and what they owe, in total, then each open
/// debt under its side, the soonest due first, and the paid ones folded
/// away below. A tick on a row marks it paid, with Undo; tapping a row
/// opens it to change or delete.
class DebtsPage extends ConsumerWidget {
  /// Creates the screen.
  const DebtsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtsProvider);
    final today = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Debts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.debtForm),
        icon: const Icon(Icons.add),
        label: const Text('Add debt'),
      ),
      body: debts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(
          icon: Icons.error_outline,
          title: 'Could not read your debts',
          body: error is Failure ? error.message : 'Please try again.',
        ),
        data: (all) {
          if (all.isEmpty) {
            // E-22: what belongs here, and how to put it there.
            return const _Message(
              icon: Icons.handshake_outlined,
              title: 'No debts yet',
              body:
                  'Tap Add debt to record money you lent or borrowed, and '
                  'tick it off when it is paid back.',
            );
          }

          final owedToMe = [
            for (final d in all)
              if (d.isOpen && d.direction == DebtDirection.owedToMe) d,
          ];
          final iOwe = [
            for (final d in all)
              if (d.isOpen && d.direction == DebtDirection.iOwe) d,
          ];
          final paid = [
            for (final d in all)
              if (!d.isOpen) d,
          ];

          return ListView(
            // Room for the button, or it covers the last row.
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              _TotalsCard(totals: DebtTotals.of(all, today: today)),
              if (owedToMe.isNotEmpty) ...[
                const _Heading('Owed to you'),
                for (final debt in owedToMe)
                  _DebtTile(key: ValueKey(debt.id), debt: debt, today: today),
              ],
              if (iOwe.isNotEmpty) ...[
                const _Heading('You owe'),
                for (final debt in iOwe)
                  _DebtTile(key: ValueKey(debt.id), debt: debt, today: today),
              ],
              if (paid.isNotEmpty)
                ExpansionTile(
                  title: Text('Paid · ${paid.length}'),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  children: [
                    for (final debt in paid)
                      _DebtTile(
                        key: ValueKey(debt.id),
                        debt: debt,
                        today: today,
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// What is still owed each way, and how many debts are overdue.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final DebtTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    Widget figure(String label, int cents, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          ScaleDownText(
            formatCents(cents),
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                figure('Owed to you', totals.owedToMeCents, colors.income),
                const SizedBox(width: 12),
                figure('You owe', totals.iOweCents, colors.expense),
              ],
            ),
            if (totals.overdue > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  totals.overdue == 1
                      ? '1 debt is overdue.'
                      : '${totals.overdue} debts are overdue.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// One debt: who, what for, when it is due or was paid, how much — green
/// owed to the user, red owed by them — and a tick to mark it paid.
class _DebtTile extends ConsumerWidget {
  const _DebtTile({required this.debt, required this.today, super.key});

  final Debt debt;
  final DateTime today;

  Future<void> _markPaid(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(debtActionsControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final failure = await actions.setPaid(debt, paidOn: today);
    messenger.clearSnackBars();
    if (failure != null) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('${debt.person}: marked as paid'),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => actions.setPaid(debt, paidOn: null),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final owedToMe = debt.direction == DebtDirection.owedToMe;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final tint = debt.isOpen
        ? (owedToMe ? colors.income : colors.expense)
        : muted;
    final overdue = debt.isOverdue(today);
    final day = DateFormat.yMMMd();

    final when = switch (debt) {
      Debt(paidOn: final paid?) => 'Paid ${day.format(paid)}',
      Debt(dueOn: final due?) when overdue =>
        'Overdue since ${day.format(due)}',
      Debt(dueOn: final due?) => 'Due ${day.format(due)}',
      _ => 'Since ${day.format(debt.incurredOn)}',
    };
    final note = debt.note;

    return ListTile(
      onTap: () => context.push(Routes.debtForm, extra: debt),
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: 0.12),
        child: Icon(
          // Money coming back to the user, or going out from them.
          owedToMe ? Icons.call_received : Icons.call_made,
          color: tint,
          size: 20,
        ),
      ),
      title: Text(debt.person, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [?note, when].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: overdue ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleDownText(
            formatCents(debt.amountCents),
            style: theme.textTheme.titleMedium?.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
              decoration: debt.isOpen ? null : TextDecoration.lineThrough,
            ),
          ),
          if (debt.isOpen)
            IconButton(
              tooltip: 'Mark as paid',
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () => _markPaid(context, ref),
            ),
        ],
      ),
    );
  }
}

/// An empty or error state: what belongs here, why it is not, what to do.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: muted),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
