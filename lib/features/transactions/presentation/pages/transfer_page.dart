import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/entry_catalog.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/account_icons.dart';
import '../../domain/usecases/make_transfer.dart';
import '../providers/transaction_providers.dart';

/// Moving money between two of your own accounts. FR-TRF-001 to FR-TRF-003.
///
/// ## Why this screen lives in `features/transactions/`
///
/// A transfer needs `MakeTransfer`, which belongs to transactions, and the
/// account list, which belongs to accounts. Whichever feature hosts the screen
/// would import the other, and rule 4 of `check_architecture.sh` forbids that.
///
/// So it sits with the use case, and reads accounts through
/// `core/database/entry_catalog.dart` — the core-owned reader the entry screen
/// already uses for the same reason. Neither feature imports the other.
///
/// ## What it deliberately does not have
///
/// No category picker: a transfer is not spending, and E-17 made
/// `category_id` nullable precisely so a transfer can carry none. No sign on
/// the amount either — direction comes from the two account fields, which is
/// why `MakeTransfer` refuses a negative one rather than interpreting it.
class TransferPage extends ConsumerStatefulWidget {
  /// Creates the transfer screen.
  const TransferPage({super.key});

  @override
  ConsumerState<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends ConsumerState<TransferPage> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  int? _fromId;
  int? _toId;
  DateTime _date = DateTime.now();

  /// Set once the user has tried to save, so the screen does not object to an
  /// empty amount before they have typed one.
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  AccountOption? _accountFrom(List<AccountOption> accounts, int? id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  TransferParams _build(List<AccountOption> accounts) {
    final from = _accountFrom(accounts, _fromId);
    final to = _accountFrom(accounts, _toId);

    return TransferParams(
      fromAccountId: _fromId ?? -1,
      toAccountId: _toId ?? -1,
      amountCents: parseToCents(_amount.text) ?? 0,
      date: _date,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      // The currencies the two accounts actually hold, so the use case can
      // apply E-25's rule rather than the screen inventing its own version.
      fromCurrency: from?.currency ?? TransferParams.defaultCurrency,
      toCurrency: to?.currency ?? TransferParams.defaultCurrency,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      // MakeTransfer allows a day of slack for a device clock in another time
      // zone, but there is no reason to offer a future date in a picker.
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(List<AccountOption> accounts) async {
    setState(() => _submitted = true);

    final params = _build(accounts);
    if (MakeTransfer.validate(params) != null) return;

    final saved = await ref
        .read(saveTransferControllerProvider.notifier)
        .save(params);

    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      return;
    }

    final error = ref.read(saveTransferControllerProvider).error;
    if (error is Failure) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(entryCatalogProvider);
    final saving = ref.watch(saveTransferControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer')),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Problem(error: error),
        data: (data) {
          final accounts = data.accounts;
          // Fewer than two accounts means there is nowhere to move money to.
          // E-22's rule: say what belongs here and the one action that fills
          // it, rather than showing two pickers that cannot be satisfied.
          if (accounts.length < 2) return const _NeedsTwoAccounts();

          _fromId ??= accounts.first.id;
          _toId ??= accounts.length > 1 ? accounts[1].id : null;

          final problem = _submitted
              ? MakeTransfer.validate(_build(accounts))
              : null;

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _AccountField(
                  label: 'From',
                  accounts: accounts,
                  selectedId: _fromId,
                  onChanged: (id) => setState(() => _fromId = id),
                  errorText: problem?.field == 'fromAccount'
                      ? problem?.message
                      : null,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Icon(Icons.arrow_downward),
                ),
                _AccountField(
                  label: 'To',
                  accounts: accounts,
                  selectedId: _toId,
                  onChanged: (id) => setState(() => _toId = id),
                  errorText: problem?.field == 'toAccount'
                      ? problem?.message
                      : null,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    hintText: '0.00',
                    border: const OutlineInputBorder(),
                    errorText: problem?.field == 'amount'
                        ? problem?.message
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(_formatDate(_date)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: _pickDate,
                ),
                if (problem?.field == 'date')
                  Text(
                    problem!.message,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    // FR-TRF-003. Shown on both halves of the transfer.
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  // Enabled even when invalid: the point of pressing it is to
                  // find out what is wrong, and a greyed button with no
                  // message beside it is a dead end.
                  onPressed: saving ? null : () => _save(accounts),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Transfer'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// One side of the transfer.
class _AccountField extends StatelessWidget {
  const _AccountField({
    required this.label,
    required this.accounts,
    required this.selectedId,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final List<AccountOption> accounts;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: selectedId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        errorText: errorText,
        // The refusal for a cross-currency pair is a sentence, not a word, so
        // it needs room rather than being clipped to one line.
        errorMaxLines: 3,
      ),
      items: [
        for (final account in accounts)
          DropdownMenuItem(
            value: account.id,
            child: Row(
              children: [
                Icon(accountIconFor(account.icon), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(account.name, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text(
                  formatCents(
                    account.balanceCents,
                    currency: CurrencyFormat.forCode(account.currency),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Shown when there is nowhere to move money to. E-22.
class _NeedsTwoAccounts extends StatelessWidget {
  const _NeedsTwoAccounts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 40, color: colors.transfer),
            const SizedBox(height: 16),
            Text(
              'A transfer moves money between two of your accounts, so you '
              'need a second one first.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add one from the accounts panel on the home screen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(switch (error) {
        final Failure failure => failure.message,
        _ => 'Could not load your accounts.',
      }, textAlign: TextAlign.center),
    ),
  );
}
