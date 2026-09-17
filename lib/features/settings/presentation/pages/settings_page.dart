import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';

/// The settings screen. SDD SCR-016.
///
/// Sections arrive with the requirements that fill them: this is the shell,
/// and the rows it draws are the ones whose use cases exist. A section for a
/// feature that is not built yet would be furniture rather than information,
/// so none is drawn ahead of its slice.
///
/// The first row is not a preference at all. "Recalculate account balances"
/// is E-18's reconciliation, reachable from here and from nowhere else:
/// `RecomputeAllAccountBalances` re-derives every cached balance from
/// history, which repairs drift that arrived from outside the app's own
/// write paths — a restored backup, a crash mid-write, a database edited by
/// hand. The app's own writes keep the cache exact inside the same
/// transaction as the row that moves it, so this is a repair to ask for, not
/// a task to schedule.
class SettingsPage extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsPage({super.key});

  /// Asks first, then runs the sweep and reports how it went. E-18.
  ///
  /// The dialog is there because the action reads every transaction of every
  /// account, and a full-history scan started by a stray tap on a settings
  /// row is exactly the kind of work that should be confirmed. The sentences
  /// shown afterwards are the controller's: the success line here, and the
  /// use case's own failure message when it refuses.
  Future<void> _recalculate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recalculate account balances?'),
        content: const Text(
          'Every balance is worked out again from its opening balance and '
          'every transaction since. Use this after restoring a backup, or if '
          'a balance does not match its transactions. Nothing is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Recalculate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final failure = await ref
        .read(recalculateBalancesControllerProvider.notifier)
        .run();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failure?.message ?? 'Account balances recalculated.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(recalculateBalancesControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            const _SectionHeader('Data'),
            ListTile(
              enabled: !busy,
              leading: busy
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calculate_outlined),
              title: const Text('Recalculate account balances'),
              subtitle: const Text(
                'Work every balance out again from its transactions. For '
                'after a restore, or when a total looks wrong.',
              ),
              onTap: busy ? null : () => _recalculate(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section label, in the style Material uses for grouped settings.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
