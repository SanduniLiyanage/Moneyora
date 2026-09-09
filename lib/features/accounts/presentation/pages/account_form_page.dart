import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/account_icons.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/account_totals.dart';
import '../../domain/usecases/add_account.dart';
import '../providers/account_providers.dart';

/// Creating and editing an account. FR-ACC-001, FR-ACC-002, FR-ACC-006.
///
/// One screen for both, because they are the same fields and a user thinks of
/// it as "the account". [initial] being null is what makes it a new one.
///
/// Every rule enforced here is [AddAccount.validate], **called** rather than
/// restated. The use case runs it again on save; this runs it as the user
/// types so a problem appears next to the field that caused it rather than
/// after they commit. Two moments, one rule — the alternative is two copies,
/// and the copy that drifts is always the one nobody is testing.
class AccountFormPage extends ConsumerStatefulWidget {
  /// Creates the form, editing [initial] when one is given.
  const AccountFormPage({super.key, this.initial});

  /// The account being edited, or null when creating one.
  final Account? initial;

  @override
  ConsumerState<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends ConsumerState<AccountFormPage> {
  late final TextEditingController _name;
  late final TextEditingController _currency;
  late final TextEditingController _openingBalance;

  late AccountType _type;
  late String _iconKey;
  late DateTime _openedOn;
  late bool _includeInTotal;

  /// Set once the user has tried to save, so the form does not shout about an
  /// empty name field before they have typed in it.
  bool _submitted = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;

    _name = TextEditingController(text: initial?.name ?? '');
    _currency = TextEditingController(
      text: initial?.currency ?? AccountTotals.defaultBaseCurrency,
    );
    _openingBalance = TextEditingController(
      text: initial == null
          ? ''
          // Without the symbol: this box is an amount to edit, not a figure to
          // read, and `Rs` in an input is something to delete before typing.
          : formatCents(initial.initialBalanceCents, showSymbol: false),
    );

    _type = initial?.type ?? AccountType.cash;
    _iconKey = initial?.icon ?? defaultAccountIconKey;
    _openedOn = initial?.initialBalanceDate ?? DateTime.now();
    _includeInTotal = initial?.includeInTotal ?? true;

    for (final controller in [_name, _currency, _openingBalance]) {
      // Rebuild as they type so the live validation below keeps up.
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  /// The account as the form currently describes it.
  ///
  /// [Account.currentBalanceCents] is deliberately carried through unchanged
  /// on an edit and left at zero on a new one: it is a cache maintained by the
  /// writes that move it (E-18), and a form that set it directly would put the
  /// cache and the history into a disagreement nothing could detect. The
  /// repository refuses to write it either way.
  Account _build() => Account(
    id: widget.initial?.id,
    name: _name.text.trim(),
    icon: _iconKey,
    type: _type,
    currency: _currency.text.trim().toUpperCase(),
    initialBalanceCents: parseToCents(_openingBalance.text) ?? 0,
    currentBalanceCents: widget.initial?.currentBalanceCents ?? 0,
    initialBalanceDate: _openedOn,
    includeInTotal: _includeInTotal,
  );

  /// The use case's own verdict on the form as it stands.
  ValidationFailure? get _problem => AddAccount.validate(_build());

  /// The message for [field], once the user has tried to save.
  String? _errorFor(String field) {
    if (!_submitted) return null;
    final problem = _problem;
    return problem != null && problem.field == field ? problem.message : null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _openedOn,
      firstDate: DateTime(2000),
      // Today, not a year out: an opening balance dated in the future is what
      // AddAccount.validate refuses, so the picker should not offer it.
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _openedOn = picked);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    // Let the use case be the one that refuses. Checking here first only
    // avoids a pointless round trip; the message shown is still its message.
    if (_problem != null) return;

    final saved = await ref
        .read(saveAccountControllerProvider.notifier)
        .save(_build());

    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      return;
    }

    final error = ref.read(saveAccountControllerProvider).error;
    if (error is Failure) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Archives the account, or restores it. FR-ACC-004.
  ///
  /// `ArchiveAccount` refuses to archive the last usable account, because
  /// doing so leaves nowhere to record a transaction and an entry screen with
  /// no account to default to — a dead end reached through a control that
  /// looks harmless. Its sentence is shown rather than swallowed.
  Future<void> _setArchived({required bool archived}) async {
    final id = widget.initial?.id;
    if (id == null) return;

    final failure = await ref
        .read(accountActionsControllerProvider.notifier)
        .setArchived(id, archived: archived);

    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    Navigator.of(context).pop();
  }

  /// Permanently removes the account. FR-ACC-007, raised by E-25.
  ///
  /// Asks first, because this is the one action here that cannot be undone —
  /// unlike archiving, which is a view filter with a restore beside it.
  /// `DeleteAccount` refuses anyway once the account has transactions, naming
  /// the count and sending the user to archive instead.
  Future<void> _delete() async {
    final id = widget.initial?.id;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this account?'),
        content: Text(
          'This removes ${widget.initial!.name} for good. An account with '
          'transactions cannot be deleted — archive it instead, so the '
          'records are kept.',
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

    if (confirmed != true || !mounted) return;

    final failure = await ref
        .read(accountActionsControllerProvider.notifier)
        .delete(id);

    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saving = ref.watch(saveAccountControllerProvider).isLoading;
    final busy = ref.watch(accountActionsControllerProvider).isLoading;
    final archived = widget.initial?.isArchived ?? false;
    final currency = _currency.text.trim().toUpperCase();
    final foreign =
        currency.isNotEmpty && currency != AccountTotals.defaultBaseCurrency;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit account' : 'New account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'Cash, Commercial Bank savings',
                border: const OutlineInputBorder(),
                errorText: _errorFor('name'),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final type in AccountType.values)
                  DropdownMenuItem(value: type, child: Text(_labelFor(type))),
              ],
              onChanged: (next) =>
                  setState(() => _type = next ?? AccountType.cash),
            ),
            const SizedBox(height: 16),
            Text('Icon', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _IconPicker(
              selectedKey: _iconKey,
              onSelected: (key) => setState(() => _iconKey = key),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _openingBalance,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Opening balance',
                      // Signed, unlike a transaction amount: a credit card
                      // legitimately opens owing money.
                      hintText: '0.00',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _currency,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 3,
                    decoration: InputDecoration(
                      labelText: 'Currency',
                      border: const OutlineInputBorder(),
                      counterText: '',
                      errorText: _errorFor('currency'),
                    ),
                  ),
                ),
              ],
            ),
            if (foreign) ...[
              const SizedBox(height: 8),
              Text(
                // E-25. Said here rather than discovered later in the panel,
                // because choosing a currency is the moment the consequence
                // becomes true, and a total that quietly omits an account is
                // worse than one that explains itself.
                'Moneyora cannot convert between currencies yet, so a $currency '
                'account is shown on its own and left out of your total '
                'balance.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Opening balance date'),
              subtitle: Text(_formatDate(_openedOn)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDate,
            ),
            if (_errorFor('initialBalanceDate') case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeInTotal,
              onChanged: (next) => setState(() => _includeInTotal = next),
              title: const Text('Include in total balance'),
              // FR-ACC-002. The toggle is not obvious without saying why it
              // exists, and its whole purpose is the case below.
              subtitle: const Text(
                'Turn this off for money that is real but not yours to spend '
                '— a shared household account, or one held for someone else.',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              // Enabled even when invalid: the point of pressing Save is to
              // find out what is wrong, and a greyed button with no message
              // beside it is a dead end.
              onPressed: saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save changes' : 'Add account'),
            ),
            // Only an account that exists can be archived or deleted. On a
            // new one there is nothing to act on, and offering the controls
            // greyed out would be furniture rather than information.
            if (_isEditing) ...[
              const Divider(height: 40),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => _setArchived(archived: !archived),
                icon: Icon(
                  archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                label: Text(archived ? 'Restore account' : 'Archive account'),
              ),
              const SizedBox(height: 8),
              Text(
                // FR-ACC-004. Archiving is the answer to "I closed that bank
                // account", and saying what it keeps is what stops someone
                // reaching for Delete instead.
                archived
                    ? 'Restoring brings it back into your account list and '
                          'your total balance.'
                    : 'Hides the account without touching its transactions, so '
                          'every past total still adds up.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                label: const Text('Delete account'),
              ),
              const SizedBox(height: 8),
              Text(
                // FR-ACC-007, raised by E-25. Stating the limit up front
                // rather than letting the refusal be the first they hear of
                // it — the use case will refuse either way, but a rule
                // discovered by being told "no" reads as the app being awkward.
                'Only possible while the account has no transactions. '
                'Otherwise archive it, so the records are kept.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _labelFor(AccountType type) => switch (type) {
    AccountType.cash => 'Cash',
    AccountType.bank => 'Bank account',
    AccountType.creditCard => 'Credit card',
    AccountType.digitalWallet => 'Digital wallet',
    AccountType.crypto => 'Cryptocurrency',
    AccountType.custom => 'Other',
  };

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// The grid of built-in icons. FR-ACC-006, as amended by E-26.
class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selectedKey, required this.onSelected});

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 96,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: accountIcons.length,
        itemBuilder: (context, index) {
          final entry = accountIcons[index];
          final selected = entry.key == selectedKey;

          return Tooltip(
            message: entry.label,
            child: InkWell(
              onTap: () => onSelected(entry.key),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: selected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  border: selected
                      ? Border.all(color: theme.colorScheme.primary, width: 2)
                      : null,
                ),
                child: Semantics(
                  label: entry.label,
                  selected: selected,
                  button: true,
                  child: Icon(
                    entry.icon,
                    color: selected ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
