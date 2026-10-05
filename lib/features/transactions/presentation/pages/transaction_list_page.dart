import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/ports/account_reader.dart';
import '../../../../core/ports/category_reader.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/category_palette.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/category_icons.dart';
import '../../../../core/widgets/scale_down_text.dart';
import '../../domain/entities/category_group.dart';
import '../../domain/entities/day_group.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../providers/transaction_providers.dart';
import 'add_transaction_page.dart';

/// SCR-005 — the transaction list. FR-EXP-006.
///
/// Watches rather than reads, so a transaction saved on the entry screen
/// appears here the moment the write commits, with no refresh and no
/// coordination between the two screens.
///
/// Scoped to the period and account the home screen's figures are for
/// ([from], [to], [accountId]), with [header] — the balance for that scope,
/// and the way to change it — above the rows. Both come from
/// `core/router/app_router.dart`, which composes the analytics feature in,
/// because this feature may not import that one. Built without them, the
/// list shows everything.
class TransactionListPage extends ConsumerStatefulWidget {
  /// Creates the list screen.
  const TransactionListPage({
    super.key,
    this.from,
    this.to,
    this.accountId,
    this.header,
  });

  /// The first day shown, or null for no lower bound.
  final DateTime? from;

  /// The last day shown, inclusive, or null for no upper bound.
  final DateTime? to;

  /// The one account shown, or null for all of them. FR-RPT-003.
  final int? accountId;

  /// Shown above the rows: the balance for this scope. FR-RPT-006.
  final Widget? header;

  /// Whether the list is narrowed to a period or an account.
  bool get isScoped => from != null || to != null || accountId != null;

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

  /// FR-EXP-011's second mode. Both modes read the same filtered rows.
  bool _byCategory = false;

  TransactionFilter get _filter => TransactionFilter(
    type: _typeFilter,
    from: widget.from,
    to: widget.to,
    accountId: widget.accountId,
  );

  bool get _isFiltered => _typeFilter != null;

  Future<void> _edit(Transaction transaction) =>
      _open(AddTransactionPage(initial: transaction));

  /// Opens [page] over the list, taking the "Transaction deleted" offer
  /// down first: it belongs to this screen, and left up it sits over the
  /// next screen's Save button. The deletion itself still completes.
  Future<void> _open(Widget page) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// Hides the row and starts the undo window. E-23.
  void _delete(Transaction transaction) {
    final id = transaction.id;
    if (id == null) return;

    final notifier = ref.read(pendingDeletionsProvider.notifier);
    notifier.schedule(id, row: transaction);

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Transaction deleted'),
            duration: PendingDeletions.window,
            persist: false,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => notifier.undo(id),
            ),
          ),
        )
        .closed
        .then((reason) {
          if (reason != SnackBarClosedReason.action) {
            notifier.commit(id);
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider(_filter));
    final pending = ref.watch(pendingDeletionsProvider);
    // Only for naming a transfer's counterparty (FR-TRF-004); the list itself
    // never waits on this, so a loading or failed catalog just falls back to
    // the bare "Transfer" label below rather than blocking the screen.
    final accountNames = <int, String>{
      for (final account
          in ref.watch(entryAccountsProvider).valueOrNull ??
              const <AccountOption>[])
        account.id: account.name,
    };
    // Names each row by its category, the same way: a catalog still loading
    // leaves the note or a bare word, never a blocked list.
    final categories = <int, CategoryOption>{
      for (final category
          in ref.watch(entryCategoriesProvider).valueOrNull ??
              const <CategoryOption>[])
        category.id: category,
    };
    final categoryNames = {
      for (final MapEntry(:key, :value) in categories.entries) key: value.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          // E-11 puts the toggle beside the balance; on this screen that is
          // the app bar, and the icon shows the mode a tap would switch to.
          IconButton(
            onPressed: () => setState(() => _byCategory = !_byCategory),
            icon: Icon(
              _byCategory
                  ? Icons.view_agenda_outlined
                  : Icons.category_outlined,
            ),
            tooltip: _byCategory ? 'List by date' : 'Group by category',
          ),
          // A transfer belongs here rather than beside the + button: it is
          // not a third kind of entry, it is moving money that is already
          // recorded, and putting it in the entry screen's type toggle would
          // say otherwise.
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              context.push(Routes.transfer);
            },
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Transfer between accounts',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _FilterBar(
            selected: _typeFilter,
            onSelected: (type) => setState(() => _typeFilter = type),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const AddTransactionPage()),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: _WithHeader(
        header: widget.header,
        child: transactions.when(
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
                  : widget.isScoped
                  ? const _Message(
                      icon: Icons.event_busy_outlined,
                      title: 'Nothing in this period',
                      body:
                          'Tap the balance above to choose another period or '
                          'account, or tap Add to record one.',
                    )
                  : const _Message(
                      icon: Icons.receipt_long_outlined,
                      title: 'No transactions yet',
                      body:
                          'Tap Add to record your first one. Everything you '
                          'enter stays on this phone.',
                    );
            }

            if (_byCategory) {
              final groups = CategoryGroup.group(rows);
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return _CategoryGroupTile(
                    // A group keeps its open or closed state as rows stream in
                    // and the order shifts under it.
                    key: ValueKey(('group', group.categoryId)),
                    group: group,
                    category: categories[group.categoryId],
                    children: [
                      for (final entry in group.entries)
                        Dismissible(
                          key: ValueKey(entry.transaction.id),
                          direction: DismissDirection.endToStart,
                          background: const _DeleteBackground(),
                          onDismissed: (_) => _delete(entry.transaction),
                          child: _TransactionTile(
                            transaction: entry.transaction,
                            accountNames: accountNames,
                            categoryNames: categoryNames,
                            amountCents: entry.amountCents,
                            inGroup: true,
                            onTap: () => _edit(entry.transaction),
                          ),
                        ),
                    ],
                  );
                },
              );
            }

            // FR-EXP-006: by day, each day's header saying what it cost.
            final days = DayGroup.group(rows);
            return ListView.builder(
              // Room for the FAB, or it covers the last row — which is the row
              // someone has just added and most wants to see.
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: days.length,
              itemBuilder: (context, index) {
                final day = days[index];
                return _DayGroupTile(
                  // A day keeps its open or closed state as rows stream in.
                  key: ValueKey(('day', day.day)),
                  group: day,
                  countTransfers: widget.accountId != null,
                  children: [
                    for (final transaction in day.transactions)
                      Dismissible(
                        key: ValueKey(transaction.id),
                        direction: DismissDirection.endToStart,
                        background: const _DeleteBackground(),
                        onDismissed: (_) => _delete(transaction),
                        child: _TransactionTile(
                          transaction: transaction,
                          accountNames: accountNames,
                          categoryNames: categoryNames,
                          showDate: false,
                          onTap: () => _edit(transaction),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// [child] under [header], when there is one: the balance stays in view
/// over an empty period, where it is the way to choose another.
class _WithHeader extends StatelessWidget {
  const _WithHeader({required this.header, required this.child});

  final Widget? header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = header;
    if (top == null) return child;
    return Column(
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: top),
        Expanded(child: child),
      ],
    );
  }
}

/// One row. Amount on the right, coloured by what it did to the balance.
class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.accountNames,
    required this.categoryNames,
    this.amountCents,
    this.inGroup = false,
    this.showDate = true,
    this.onTap,
  });

  final Transaction transaction;

  /// What to show instead of the whole amount: one split part's, when the
  /// row sits under that part's category.
  final int? amountCents;

  /// Under a category's header, where naming the category again says
  /// nothing: the note leads instead (E-11).
  final bool inGroup;

  /// False under a day's header, which already says the date.
  final bool showDate;

  /// Id-to-name, for naming a transfer's counterparty. FR-TRF-004.
  final Map<int, String> accountNames;

  /// Id-to-name, for naming what an expense or income was for. FR-EXP-006.
  final Map<int, String> categoryNames;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    final incoming =
        transaction.transferDirection == TransferDirection.incoming;
    final (tint, sign) = switch (transaction.type) {
      TransactionType.income => (colors.income, '+'),
      TransactionType.expense => (colors.expense, '−'),
      // A transfer is neither, so its icon keeps the transfer colour and
      // reads as "not spending" at a glance — E-02 on why conflating the two
      // inflates both totals.
      TransactionType.transfer => (colors.transfer, incoming ? '+' : '−'),
    };
    // Its amount, though, says which way the money went: for the account it
    // left, a transfer is money gone, and a minus in anything but red read
    // as a mistake.
    final amountTint = transaction.type == TransactionType.transfer
        ? (incoming ? colors.income : colors.expense)
        : tint;

    final note = transaction.note?.trim() ?? '';
    final date = _formatDate(transaction.date);
    final title = switch (transaction.type) {
      TransactionType.transfer => _transferLabel(),
      _ when inGroup => note.isNotEmpty ? note : date,
      _ =>
        categoryNames[transaction.categoryId] ??
            (note.isNotEmpty ? note : 'Uncategorised'),
    };
    final showNote = note.isNotEmpty && note != title;
    final subtitle = switch (showDate) {
      false => showNote ? Text(note) : null,
      _ when inGroup && title == date => null,
      _ => Text(showNote ? '$date · $note' : date),
    };

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: 0.12),
        child: Icon(
          switch (transaction.type) {
            // The way the balance moves: income up, an expense down.
            TransactionType.income => Icons.arrow_upward,
            TransactionType.expense => Icons.arrow_downward,
            TransactionType.transfer => Icons.swap_horiz,
          },
          color: tint,
          size: 20,
        ),
      ),
      title: Text(title),
      // The note goes under the name rather than replacing it: "Groceries"
      // alone does not say it was filed under Food, and a misfiled row is
      // exactly what someone scanning the list is looking for.
      subtitle: subtitle,
      trailing: _Amount(
        '$sign${formatCents(amountCents ?? transaction.amountCents)}',
        color: amountTint,
      ),
    );
  }

  /// "From X" or "To Y", per FR-TRF-004 — falling back to the bare word if
  /// the counterparty is not known yet (the catalog is still loading) or no
  /// longer in it (the account was since archived).
  String _transferLabel() {
    final name = accountNames[transaction.counterpartyAccountId];
    if (name == null) return 'Transfer';

    return transaction.transferDirection == TransferDirection.incoming
        ? 'From $name'
        : 'To $name';
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

/// One day's header, expanding to its rows. FR-EXP-006.
///
/// The date, how many rows the day holds, and what it cost: spending in the
/// expense colour, and income under it when there was any. Across every
/// account transfers are listed but not totalled (E-02); for one account
/// they move its totals ([countTransfers]). Open by default, the arrow on the left
/// so the total keeps the right edge the amounts below it line up with.
class _DayGroupTile extends StatelessWidget {
  const _DayGroupTile({
    required this.group,
    required this.children,
    required this.countTransfers,
    super.key,
  });

  final DayGroup group;
  final List<Widget> children;

  /// Whether the day's transfers move its totals: when the list shows one
  /// account, a transfer out of it is money gone and a transfer in is money
  /// arrived. Across every account each transfer's legs would cancel and
  /// only inflate both lines, so they are left out (E-02). FR-TRF-004.
  final bool countTransfers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final spent =
        group.spentCents + (countTransfers ? group.transferOutCents : 0);
    final income =
        group.incomeCents + (countTransfers ? group.transferInCents : 0);

    return ExpansionTile(
      initiallyExpanded: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Row(
        children: [
          Flexible(
            child: Text(
              dayLabel(group.day, DateTime.now()),
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            label: Text('${group.count}'),
            backgroundColor: theme.colorScheme.secondaryContainer,
            textColor: theme.colorScheme.onSecondaryContainer,
          ),
        ],
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // A day of transfers alone has no total, not a red "−Rs0.00":
          // nothing was spent, and a zero with a minus reads as a loss.
          if (spent > 0)
            _Amount('−${formatCents(spent)}', color: colors.expense),
          if (income > 0)
            _Amount('+${formatCents(income)}', color: colors.income),
        ],
      ),
      shape: const Border(),
      collapsedShape: const Border(),
      children: children,
    );
  }
}

/// A day header's date: "Today", "Yesterday", else the weekday and date,
/// with the year only when it is not this one.
String dayLabel(DateTime day, DateTime now) {
  if (DateUtils.isSameDay(day, now)) return 'Today';
  if (DateUtils.isSameDay(day, DateTime(now.year, now.month, now.day - 1))) {
    return 'Yesterday';
  }
  return day.year == now.year
      ? DateFormat('EEEE, d MMMM').format(day)
      : DateFormat('EEEE, d MMMM y').format(day);
}

/// One category's header, expanding to its rows. FR-EXP-011.
///
/// E-11's header: the category's icon and name, how many rows it holds, and
/// their total. Transfers get the header without a total (E-02).
class _CategoryGroupTile extends StatelessWidget {
  const _CategoryGroupTile({
    required this.group,
    required this.category,
    required this.children,
    super.key,
  });

  final CategoryGroup group;

  /// Null for transfers, or while the catalog is still loading.
  final CategoryOption? category;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    final (icon, tint, name) = switch (category) {
      _ when group.isTransfers => (
        Icons.swap_horiz,
        colors.transfer,
        'Transfers',
      ),
      final CategoryOption category => (
        categoryIconFor(category.icon),
        categoryColorFor(category.colorHex, theme.brightness),
        category.name,
      ),
      null => (
        Icons.category_outlined,
        theme.colorScheme.onSurfaceVariant,
        'Uncategorised',
      ),
    };

    final net = group.netCents;
    final total = switch (net) {
      _ when group.isTransfers => null,
      > 0 => ('+${formatCents(net)}', colors.income),
      < 0 => ('−${formatCents(-net)}', colors.expense),
      _ => (formatCents(0), theme.colorScheme.onSurfaceVariant),
    };

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: 0.12),
        child: Icon(icon, color: tint, size: 20),
      ),
      title: Row(
        children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Badge(
            label: Text('${group.count}'),
            backgroundColor: theme.colorScheme.secondaryContainer,
            textColor: theme.colorScheme.onSecondaryContainer,
          ),
        ],
      ),
      trailing: total == null ? null : _Amount(total.$1, color: total.$2),
      childrenPadding: const EdgeInsets.only(left: 16),
      shape: const Border(),
      children: children,
    );
  }
}

/// An amount at a row's end. At the largest font a seven-figure amount is
/// wider than a 320dp phone, and a `ListTile` whose trailing widget takes
/// the whole row throws rather than lays out; [ScaleDownText] caps it.
class _Amount extends StatelessWidget {
  const _Amount(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => ScaleDownText(
    text,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(color: color, fontWeight: FontWeight.w600),
  );
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
    // 0.7, as the rest of the app's muted text: 0.6 is 4.45:1 on the
    // light surface, just under SRS §4.1's floor.
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    // Scrolls: at the largest font on a small phone the three lines and the
    // action are taller than the space under the app bar.
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
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
