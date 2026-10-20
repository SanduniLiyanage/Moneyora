import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/scale_down_text.dart';
import '../../../../injection.dart' show clockProvider;
import '../../domain/entities/debt.dart';
import '../../domain/entities/debt_person.dart';
import '../../domain/entities/debt_totals.dart';
import '../../domain/usecases/rename_person.dart';
import '../providers/debt_providers.dart';

/// Money owed, either way, person by person. FR-DBT-002, FR-DBT-005,
/// E-42, E-47.
///
/// What is owed to the user and what they owe, in total, then one row per
/// person with something still open: what they owe the user, or the user
/// owes them, net of every open record either way. A row opens to the
/// records behind it, each still ticked paid with Undo or opened to change
/// or delete, and to the person's own actions. People with nothing open
/// are folded away below. The app bar's split icon shares a bill between
/// several people (FR-DBT-004).
class DebtsPage extends ConsumerWidget {
  /// Creates the screen.
  const DebtsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtsProvider);
    final today = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debts'),
        actions: [
          IconButton(
            tooltip: 'Split a bill',
            icon: const Icon(Icons.call_split),
            onPressed: () => context.push(Routes.splitBill),
          ),
        ],
      ),
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
                  'tick it off when it is paid back. A bill shared with '
                  'friends is split from the icon at the top.',
            );
          }

          final people = DebtPerson.group(all, today: today);
          final open = [
            for (final p in people)
              if (p.hasOpen) p,
          ];
          final settled = [
            for (final p in people)
              if (!p.hasOpen) p,
          ];

          return ListView(
            // Room for the button, or it covers the last row.
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              _TotalsCard(totals: DebtTotals.ofPeople(people, today: today)),
              for (final person in open)
                _PersonTile(
                  key: ValueKey(person.key),
                  person: person,
                  everyone: people,
                  today: today,
                ),
              if (settled.isNotEmpty)
                ExpansionTile(
                  title: Text('Settled · ${settled.length}'),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  children: [
                    for (final person in settled)
                      _PersonTile(
                        key: ValueKey(person.key),
                        person: person,
                        everyone: people,
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

/// What is still owed each way, how it is worked out, and how many people
/// are overdue.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final DebtTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);

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
            const SizedBox(height: 8),
            // How the two figures are reached, since a person owed both
            // ways is counted once, on one side (E-47).
            Text(
              'Worked out person by person: what each one owes you, less '
              'what you owe them.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            if (totals.overdue > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  totals.overdue == 1
                      ? '1 person is overdue.'
                      : '${totals.overdue} people are overdue.',
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

/// One person: who, and what is owed between you on balance, opening to
/// the records behind it and what can be done with them all. FR-DBT-005.
class _PersonTile extends ConsumerWidget {
  const _PersonTile({
    required this.person,
    required this.everyone,
    required this.today,
    super.key,
  });

  final DebtPerson person;

  /// Every person listed, to tell a rename that puts two together.
  final List<DebtPerson> everyone;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final net = person.netCents;
    final tint = !person.hasOpen || net == 0
        ? muted
        : (net > 0 ? colors.income : colors.expense);
    final overdue = person.isOverdue(today);

    final (standing, icon) = switch (net) {
      _ when !person.hasOpen => ('Settled', Icons.check_circle_outline),
      > 0 => ('Owes you ${formatCents(net)}', Icons.call_received),
      < 0 => ('You owe ${formatCents(-net)}', Icons.call_made),
      _ => ('All square', Icons.check_circle_outline),
    };

    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: 0.12),
        child: Icon(icon, color: tint, size: 20),
      ),
      title: Text(person.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: standing,
              style: TextStyle(color: tint, fontWeight: FontWeight.w600),
            ),
            if (overdue)
              TextSpan(
                text: ' · overdue',
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
      ),
      childrenPadding: const EdgeInsetsDirectional.only(start: 16),
      children: [
        for (final debt in person.records)
          _DebtTile(key: ValueKey(debt.id), debt: debt, today: today),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _rename(context, ref),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Rename'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Asks for the new name, and before putting two people together.
  /// FR-DBT-006.
  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(debtActionsControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final typed = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(name: person.name),
    );
    if (typed == null || !context.mounted) return;

    final other = everyone
        .where((p) => p.key == personKey(typed) && p.key != person.key)
        .firstOrNull;
    if (other != null) {
      final together = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Put them with ${other.name}?'),
          content: Text(
            '${other.name} is already in your debts. ${person.name}\'s '
            'records will be listed with theirs, as one person, and '
            'netted together. Each record stays as it is.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Put together'),
            ),
          ],
        ),
      );
      if (together != true) return;
    }

    // One spelling for the one person: the one already listed.
    final to = other?.name ?? typed;
    final failure = await actions.rename(person, to: to);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure?.message ??
              (other != null ? 'Put with ${other.name}' : 'Renamed to $to'),
        ),
      ),
    );
  }
}

/// The new name for a person, refused in [RenamePerson.validate]'s words.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});

  final String name;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.name);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final problem = RenamePerson.validate(_controller.text);
    if (problem != null) {
      setState(() => _error = problem.message);
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: 'Name',
        helperText: 'On every one of their records',
        helperMaxLines: 2,
        errorText: _error,
        errorMaxLines: 3,
      ),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _done, child: const Text('Rename')),
    ],
  );
}

/// One record with a person: what it was, when it is due or was paid, how
/// much — green owed to the user, red owed by them — and a tick to mark it
/// paid.
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

    // What it was: the user's own words, or which way it runs.
    final what = switch (debt.note) {
      final note? => note,
      null => owedToMe ? 'Owed to you' : 'You owe',
    };
    final when = switch (debt) {
      Debt(paidOn: final paid?) => 'Paid ${day.format(paid)}',
      Debt(dueOn: final due?) when overdue =>
        'Overdue since ${day.format(due)}',
      Debt(dueOn: final due?) => 'Due ${day.format(due)}',
      _ => 'Since ${day.format(debt.incurredOn)}',
    };
    final figure = formatCents(debt.amountCents);
    final figureStyle = theme.textTheme.titleMedium?.copyWith(
      color: tint,
      fontWeight: FontWeight.w600,
      decoration: debt.isOpen ? null : TextDecoration.lineThrough,
    );
    final details = Text(
      when,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: overdue ? TextStyle(color: theme.colorScheme.error) : null,
    );
    final tick = debt.isOpen
        ? IconButton(
            tooltip: 'Mark as paid',
            icon: const Icon(Icons.check_circle_outline),
            onPressed: () => _markPaid(context, ref),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Beside the amount and the tick, at the largest font on a 320dp
        // phone, the name was left 16px. Where it would have less than
        // [_nameFloor], the amount moves under it and the name has the row.
        final beside =
            constraints.maxWidth -
            _rowChrome -
            _widthOf(context, figure, figureStyle) -
            (tick == null ? 0 : AppTheme.minTouchTarget);
        final stacked = beside < _nameFloor;

        return ListTile(
          onTap: () => context.push(Routes.debtForm, extra: debt),
          leading: Icon(
            // Money coming back to the user, or going out from them.
            owedToMe ? Icons.call_received : Icons.call_made,
            color: tint,
            size: 20,
          ),
          title: Text(
            what,
            maxLines: stacked ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ScaleDownText(
                      figure,
                      style: figureStyle,
                      alignment: AlignmentDirectional.centerStart,
                      maxWidthFactor: 1,
                    ),
                    details,
                  ],
                )
              : details,
          trailing: stacked
              ? tick
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleDownText(figure, style: figureStyle),
                    ?tick,
                  ],
                ),
        );
      },
    );
  }

  /// The least room the name keeps beside the amount and the tick.
  static const _nameFloor = 96.0;

  /// The rest of a row: the padding either side, the icon, and the gaps
  /// beside the name (Material 3's 16 + 24 + 16 + 16 + 24), with the
  /// person's indent (16).
  static const _rowChrome = 112.0;

  /// [text]'s width at the user's font size, no wider than [ScaleDownText]
  /// lets it be.
  static double _widthOf(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return math.min(width, MediaQuery.sizeOf(context).width * 0.45);
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
