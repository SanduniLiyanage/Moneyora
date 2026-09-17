import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../domain/entities/user_settings.dart';
import '../../domain/usecases/set_base_currency.dart';
import '../providers/settings_providers.dart';

/// The settings screen. SDD SCR-016.
///
/// Sections arrive with the requirements that fill them: the rows it draws
/// are the ones whose use cases exist. A section for a feature that is not
/// built yet would be furniture rather than information, so none is drawn
/// ahead of its slice.
///
/// *Appearance* holds FR-SET-001's theme choice. The three options are the
/// three values `users.theme` can hold, and choosing one is drawn by the app
/// root the moment it is stored — this screen writes and never sets a theme
/// itself.
///
/// *Currency* holds FR-SET-003: the base currency totals are expressed in,
/// and the rate table (its own screen). Neither converts anything by itself
/// — conversion is FR-ACC-005's, and lands beside the totals it changes.
///
/// *Data*'s row is not a preference at all. "Recalculate account balances"
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

  /// Stores [mode], and shows the failure if it could not be. FR-SET-001.
  ///
  /// Nothing to confirm and nothing to say on success: the screen changing
  /// colour is the confirmation.
  Future<void> _setTheme(
    BuildContext context,
    WidgetRef ref,
    AppThemeMode mode,
  ) async {
    final failure = await ref.read(themeControllerProvider.notifier).set(mode);
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }

  /// Asks for a three-letter code, stores it, shows the failure if any.
  /// FR-SET-003.
  Future<void> _setBaseCurrency(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => _BaseCurrencyDialog(initial: current),
    );
    if (code == null || !context.mounted) return;

    final failure = await ref
        .read(baseCurrencyControllerProvider.notifier)
        .set(code);
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }

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
    final settings = ref.watch(settingsProvider);
    final theme = settings.asData?.value.theme;
    final baseCurrency = settings.asData?.value.currency;
    final rateCount = ref.watch(exchangeRatesProvider).asData?.value.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            const _SectionHeader('Appearance'),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Theme'),
              // The stored choice, or its failure's own sentence while there
              // is no choice to show. Loading shows neither: the row is not
              // interactive until the value it would be changing is known.
              subtitle: switch (settings) {
                AsyncError(:final Failure error) => Text(error.message),
                _ => null,
              },
            ),
            if (theme != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<AppThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: AppThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.phone_android_outlined),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {theme},
                  onSelectionChanged: (chosen) =>
                      _setTheme(context, ref, chosen.single),
                ),
              ),
            const _SectionHeader('Currency'),
            ListTile(
              leading: const Icon(Icons.currency_exchange_outlined),
              title: const Text('Base currency'),
              subtitle: Text(
                baseCurrency == null
                    ? 'The currency your total balance is shown in.'
                    : '$baseCurrency — the currency your total balance is '
                          'shown in.',
              ),
              enabled: baseCurrency != null,
              onTap: baseCurrency == null
                  ? null
                  : () => _setBaseCurrency(context, ref, baseCurrency),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_outlined),
              title: const Text('Exchange rates'),
              subtitle: Text(switch (rateCount) {
                null =>
                  'The rates used to count other currencies in your '
                      'total.',
                0 =>
                  'None yet. Add one to count an account held in another '
                      'currency.',
                1 => 'One rate.',
                final n => '$n rates.',
              }),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.exchangeRates),
            ),
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

/// Asking for the base currency. Returns the code, or null on cancel.
class _BaseCurrencyDialog extends StatefulWidget {
  const _BaseCurrencyDialog({required this.initial});

  final String initial;

  @override
  State<_BaseCurrencyDialog> createState() => _BaseCurrencyDialogState();
}

class _BaseCurrencyDialogState extends State<_BaseCurrencyDialog> {
  late final TextEditingController _code = TextEditingController(
    text: widget.initial,
  );
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// The use case's own verdict, shown as the user types once they have
  /// tried to save.
  String? get _error =>
      _submitted ? SetBaseCurrency.validate(_code.text)?.message : null;

  void _save() {
    setState(() => _submitted = true);
    if (SetBaseCurrency.validate(_code.text) != null) return;
    Navigator.of(context).pop(_code.text.trim().toUpperCase());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Base currency'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 3,
          decoration: InputDecoration(
            labelText: 'Currency code',
            hintText: 'LKR',
            counterText: '',
            errorText: _error,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          // E-34: rates are per pair, so a new base means the rates to it
          // may not exist yet. Said here, where the choice is made.
          'Accounts in other currencies count towards your total only '
          'once a rate to this currency is entered under Exchange rates.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
