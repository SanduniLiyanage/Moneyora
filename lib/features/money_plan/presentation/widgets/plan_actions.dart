import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/money_plan.dart';
import '../providers/money_plan_providers.dart';

/// Asks for a new name for [plan] and writes it. FR-PLN-015.
///
/// Shared by the plan list and the plan itself, so the two cannot drift.
Future<void> renamePlan(
  BuildContext context,
  WidgetRef ref,
  MoneyPlan plan,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(current: plan.name),
  );
  if (name == null || !context.mounted) return;

  final written = await ref
      .read(planHousekeepingControllerProvider.notifier)
      .rename(plan.id!, name);
  if (!context.mounted) return;
  _report(context, ref, written ? 'Renamed to ${name.trim()}.' : null);
}

/// Asks before deleting [plan], then deletes it. True when it is gone.
/// FR-PLN-015.
///
/// The confirmation says what goes and what stays, and the two things a
/// delete quietly changes: an active plan leaves nothing tracked, and an
/// overspend chosen to carry over has nowhere to come off.
Future<bool> deletePlan(
  BuildContext context,
  WidgetRef ref,
  MoneyPlan plan,
) async {
  final carries = plan.allocations.any((a) => a.carryOverCents > 0);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete ${plan.name}?'),
      content: Text(
        [
          'Its budgets go with it. Your transactions stay as they are.',
          if (plan.isActive)
            'Nothing is tracked until you activate another plan.',
          if (carries)
            "The overspend it carries over won't come off the next plan "
                'you make.',
        ].join('\n\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final deleted = await ref
      .read(planHousekeepingControllerProvider.notifier)
      .delete(plan.id!);
  if (!context.mounted) return deleted;
  _report(context, ref, deleted ? '${plan.name} deleted.' : null);
  return deleted;
}

/// [done] on success; otherwise the use case's own sentence.
void _report(BuildContext context, WidgetRef ref, String? done) {
  final message =
      done ??
      switch (ref.read(planHousekeepingControllerProvider).error) {
        final Failure failure => failure.message,
        _ => 'Could not change the plan.',
      };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.current)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.current.length,
        );
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _problem = 'Give the plan a name.');
      return;
    }
    Navigator.of(context).pop(_name.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Rename plan'),
    content: TextField(
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: 'Name', errorText: _problem),
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
