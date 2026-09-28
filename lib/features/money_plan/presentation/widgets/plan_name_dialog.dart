import 'package:flutter/material.dart';

/// What the user chose in [PlanNameDialog].
typedef PlanNameChoice = ({String name, bool activate});

/// Asks what to call a plan and whether to track it now. FR-PLN-015.
///
/// Returns both, or null when dismissed. Saving without activating is
/// FR-PLN-015's "June Vacation Plan" kept beside the "Regular Monthly" still
/// being tracked. Shared by the review screen and the plan editor, so a plan
/// is named the same way however it was made.
class PlanNameDialog extends StatefulWidget {
  /// Creates the dialog, the name field starting at [initial].
  const PlanNameDialog({required this.initial, super.key});

  /// The suggested name — the period's own label.
  final String initial;

  /// Shows the dialog over [context].
  static Future<PlanNameChoice?> show(
    BuildContext context, {
    required String initial,
  }) => showDialog<PlanNameChoice>(
    context: context,
    builder: (_) => PlanNameDialog(initial: initial),
  );

  @override
  State<PlanNameDialog> createState() => _PlanNameDialogState();
}

class _PlanNameDialogState extends State<PlanNameDialog> {
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
