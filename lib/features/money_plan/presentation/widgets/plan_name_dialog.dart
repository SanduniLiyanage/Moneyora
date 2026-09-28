import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/budget_alerts_switch.dart';
import '../../../../injection.dart' show budgetAlertsSwitchProvider;

/// What the user chose in [PlanNameDialog].
typedef PlanNameChoice = ({String name, bool activate, bool alerts});

/// Asks what to call a plan, whether to track it now, and — when budget
/// alerts are off — whether to hear when a category nears or passes its
/// limit. FR-PLN-015, FR-SET-007.
///
/// Returns the choices, or null when dismissed. Saving without activating is
/// FR-PLN-015's "June Vacation Plan" kept beside the "Regular Monthly" still
/// being tracked. Shared by the review screen and the plan editor, so a plan
/// is named the same way however it was made.
///
/// Alerts are off until turned on (E-35), and a plan just saved for
/// tracking is the moment they are worth offering: otherwise a user
/// overspends and hears nothing unless they found the switch in Settings.
class PlanNameDialog extends StatefulWidget {
  /// Creates the dialog, the name field starting at [initial].
  const PlanNameDialog({
    required this.initial,
    this.offerAlerts = false,
    super.key,
  });

  /// The suggested name — the period's own label.
  final String initial;

  /// Whether to offer to turn budget alerts on: true when they are off.
  final bool offerAlerts;

  /// Shows the dialog over [context].
  static Future<PlanNameChoice?> show(
    BuildContext context, {
    required String initial,
    bool offerAlerts = false,
  }) => showDialog<PlanNameChoice>(
    context: context,
    builder: (_) => PlanNameDialog(initial: initial, offerAlerts: offerAlerts),
  );

  /// The switch to turn alerts on with when [choice] asked for them, or
  /// null. Read before the caller navigates away, while [ref] is live.
  static Future<BudgetAlertsSwitch?> alertsFor(
    WidgetRef ref,
    PlanNameChoice choice,
  ) async => choice.alerts && choice.activate
      ? ref.read(budgetAlertsSwitchProvider.future)
      : null;

  /// Turns [alerts] on and says how that went through [messenger], taken
  /// before the caller navigated away.
  static Future<void> turnOn(
    BudgetAlertsSwitch alerts,
    ScaffoldMessengerState messenger,
  ) async {
    final result = await alerts.turnOn();
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.fold(
              (Failure failure) => failure.message,
              (_) =>
                  'Budget alerts are on: you will hear at 80% and at 100% '
                  'of each budget.',
            ),
          ),
        ),
      );
  }

  @override
  State<PlanNameDialog> createState() => _PlanNameDialogState();
}

class _PlanNameDialogState extends State<PlanNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );
  bool _activate = true;
  bool _alerts = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop((
    name: _name.text,
    activate: _activate,
    alerts: widget.offerAlerts && _alerts,
  ));

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Name your plan'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          // Not focused on open: the name is already filled in, and a
          // keyboard on a small phone would push the choices below it
          // out of sight.
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
        if (widget.offerAlerts && _activate)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _alerts,
            onChanged: (v) => setState(() => _alerts = v ?? true),
            title: const Text('Alert me near and over each limit'),
            subtitle: const Text(
              "A notification at 80% and at 100% of a category's budget.",
            ),
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
