import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../providers/transaction_providers.dart';
import 'add_transaction_page.dart';

/// SCR-005 — the transaction list. FR-EXP-006.
///
/// Watches rather than reads, so a transaction saved on the entry screen
/// appears here the moment the write commits, with no refresh and no
/// coordination between the two screens.
class TransactionListPage extends ConsumerStatefulWidget {
  /// Creates the list screen.
  const TransactionListPage({super.key});

  @override
  ConsumerState<TransactionListPage> createState() =>
      _TransactionListPageState();
}

class _TransactionListPageState extends ConsumerState<TransactionListPage> {
  /// Null means "everything"; a value means the user narrowed it.
  ///
  /// Kept here rather than in the filter itself because the screen needs to
  /// tell two situations apart that look identical in the data: nothing
  /// recorded yet, and nothing matching what was asked for (E-22).
  TransactionType? _typeFilter;

  TransactionFilter get _filter => TransactionFilter(type: _typeFilter);

  bool get _isFiltered => _typeFilter != null;

  Future<void> _edit(Transaction transaction) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AddTransactionPage(initial: transaction),
    ),
  );

  /// Hides the row and starts the undo window. E-23.
  void _delete(Transaction transaction) {
    final id = transaction.id;
    if (id == null) return;

    ref.read(pendingDeletionsProvider.notifier).schedule(id);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Transaction deleted'),
          // The same window the controller is counting down, so the offer
          // disappears exactly when it stops being true.
          duration: PendingDeletions.window,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                ref.read(pendingDeletionsProvider.notifier).undo(id),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider(_filter));
    final pending = ref.watch(pendingDeletionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _FilterBar(
            selected: _typeFilter,
            onSelected: (type) => setState(() => _typeFilter = type),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AddTransactionPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: transactions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(
          icon: Icons.error_outline,
          title: 'Could not load your transactions',
          body: failureMessage(error) ?? 'Please try again.',
        ),
        data: (all) {
          // A row inside its undo window is gone as far as this screen is
          // concerned, even though nothing has been written yet (E-23).
          final rows = all.where((t) => !pending.contains(t.id)).toList();

          if (rows.isEmpty) {
            // E-22. The two empty states are genuinely different situations,
            // and telling someone with a filter on to "add your first
            // expense" is the bug that distinction exists to prevent.
            return _isFiltered
                ? _Message(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'Nothing matches this filter',
                    body: 'No ${_typeFilter!.name} recorded yet.',
                    action: TextButton(
                      onPressed: () => setState(() => _typeFilter = null),
                      child: const Text('Show everything'),
                    ),
                  )
                : const _Message(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions yet',
                    body:
                        'Tap Add to record your first one. Everything you '
                        'enter stays on this phone.',
                  );
          }

          return ListView.separated(
            // Room for the FAB, or it covers the last row — which is the row
            // someone has just added and most wants to see.
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final transaction = rows[index];
              return Dismissible(
                key: ValueKey(transaction.id),
                direction: DismissDirection.endToStart,
                background: const _DeleteBackground(),
                onDismissed: (_) => _delete(transaction),
                child: _TransactionTile(
                  transaction: transaction,
                  onTap: () => _edit(transaction),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One row. Amount on the right, coloured by what it did to the balance.
class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction, this.onTap});

  final Transaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    final (tint, sign) = switch (transaction.type) {
      TransactionType.income => (colors.income, '+'),
      TransactionType.expense => (colors.expense, '−'),
      // A transfer is neither, and is tinted so it reads as "not spending" at
      // a glance — E-02 on why conflating the two inflates both totals.
      TransactionType.transfer => (
        colors.transfer,
        transaction.transferDirection == TransferDirection.incoming ? '+' : '−',
      ),
    };

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: 0.12),
        child: Icon(
          switch (transaction.type) {
            TransactionType.income => Icons.arrow_downward,
            TransactionType.expense => Icons.arrow_upward,
            TransactionType.transfer => Icons.swap_horiz,
          },
          color: tint,
          size: 20,
        ),
      ),
      title: Text(
        transaction.note?.isNotEmpty ?? false
            ? transaction.note!
            : switch (transaction.type) {
                TransactionType.transfer => 'Transfer',
                _ => 'Uncategorised',
              },
      ),
      subtitle: Text(_formatDate(transaction.date)),
      trailing: Text(
        '$sign${formatCents(transaction.amountCents)}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: tint,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final today = DateTime.now();
    if (DateUtils.isSameDay(date, today)) return 'Today';
    if (DateUtils.isSameDay(date, today.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

/// What shows behind a row being swiped away.
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return ColoredBox(
      color: colors.expense,
      child: const Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(right: 24),
          child: Icon(Icons.delete_outline, color: Colors.white),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final TransactionType? selected;
  final ValueChanged<TransactionType?> onSelected;

  @override
  Widget build(BuildContext context) {
    // Scrolls horizontally. Three chips already overflow a 360dp phone, and
    // the date-range and account filters of FR-RPT-003 are still to come — a
    // Row that fits today would only break again with the next one.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          for (final (label, value) in <(String, TransactionType?)>[
            ('All', null),
            ('Expenses', TransactionType.expense),
            ('Income', TransactionType.income),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: selected == value,
                onSelected: (_) => onSelected(value),
              ),
            ),
        ],
      ),
    );
  }
}

/// An empty or error state: what belongs here, why it is not, what to do.
///
/// E-22 requires all three. An illustration with no words is decoration; a
/// message with no action leaves the user reading rather than doing.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Center(
      child: Padding(
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
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
