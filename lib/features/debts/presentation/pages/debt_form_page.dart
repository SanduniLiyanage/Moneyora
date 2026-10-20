import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/account_reader.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/debt.dart';
import '../../domain/entities/debt_person.dart';
import '../../domain/usecases/save_debt.dart';
import '../providers/debt_providers.dart';
import '../widgets/debt_account_field.dart';
import '../widgets/person_name_field.dart';

/// Recording a debt, or changing, settling or deleting one; a payment
/// too. FR-DBT-001, FR-DBT-003, FR-DBT-008.
///
/// One screen for both, as the account form is; [initial] without an id
/// makes it a new one. A payment is [initial] with [Debt.isPayment] set,
/// its person and the way it runs filled in by the list: who paid whom,
/// how much, and on which day, with no due day and no Mark as paid,
/// since it is money already moved. Every refusal is [SaveDebt.validate]'s,
/// shown beside the field it is about once Save has been pressed.
class DebtFormPage extends ConsumerStatefulWidget {
  /// Creates the form, editing [initial] when one is given.
  const DebtFormPage({super.key, this.initial});

  /// The debt being changed; one with no id to start a new one from, as
  /// a payment is; or null for a new debt.
  final Debt? initial;

  @override
  ConsumerState<DebtFormPage> createState() => _DebtFormPageState();
}

class _DebtFormPageState extends ConsumerState<DebtFormPage> {
  late DebtDirection _direction;
  late final TextEditingController _person;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _incurredOn;
  DateTime? _dueOn;

  /// The account the money moved through, and the one it was paid back
  /// through; null for none. FR-DBT-009.
  int? _accountId;
  int? _paidAccountId;

  /// Set once the user has tried to save, so an empty form does not
  /// complain before anything has been typed.
  bool _submitted = false;

  bool get _isEditing => widget.initial?.id != null;

  bool get _isPayment => widget.initial?.isPayment ?? false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _direction = initial?.direction ?? DebtDirection.owedToMe;
    _person = TextEditingController(text: initial?.person ?? '');
    _amount = TextEditingController(
      text: initial == null || initial.amountCents == 0
          ? ''
          : formatCents(initial.amountCents, showSymbol: false),
    );
    _note = TextEditingController(text: initial?.note ?? '');
    _incurredOn = initial?.incurredOn ?? DateTime.now();
    _dueOn = initial?.dueOn;
    _accountId = initial?.accountId;
    _paidAccountId = initial?.paidAccountId;
    for (final controller in [_person, _amount]) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The debt as the form describes it. An amount that is not a number is
  /// zero, which the use case refuses in its own words.
  Debt _build() => Debt(
    id: widget.initial?.id,
    direction: _direction,
    person: _person.text,
    amountCents: parseToCents(_amount.text) ?? 0,
    note: _note.text,
    incurredOn: _incurredOn,
    dueOn: _isPayment ? null : _dueOn,
    paidOn: widget.initial?.paidOn,
    isPayment: _isPayment,
    accountId: _accountId,
    paidAccountId: _paidAccountId,
  );

  /// What would settle the person in the field, paid the way the payment
  /// runs: their net without this record, when the payment takes it
  /// towards nothing. Null otherwise. FR-DBT-008.
  int? _settlingAmount(List<Debt> all) {
    final key = personKey(_person.text);
    if (key.isEmpty) return null;
    final id = widget.initial?.id;
    final theirs = [
      for (final d in all)
        if (d.id != id && personKey(d.person) == key) d,
    ];
    if (theirs.isEmpty) return null;
    final net = DebtPerson(name: _person.text, records: theirs).netCents;
    return switch (_direction) {
      DebtDirection.iOwe when net > 0 => net,
      DebtDirection.owedToMe when net < 0 => -net,
      _ => null,
    };
  }

  String? _errorFor(String field) {
    if (!_submitted) return null;
    final problem = SaveDebt.validate(_build());
    return problem?.field == field ? problem!.message : null;
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (SaveDebt.validate(_build()) != null) return;

    final saved = await ref
        .read(saveDebtControllerProvider.notifier)
        .save(_build());
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      return;
    }
    _say(ref.read(saveDebtControllerProvider).error);
  }

  /// Paid today, or open again.
  /// Paid today, or open again. Paid, it asks which account the money came
  /// back into or left from, the debt's own first (FR-DBT-009).
  Future<void> _togglePaid() async {
    final initial = widget.initial;
    if (initial == null) return;
    int? through;
    if (initial.isOpen) {
      final accounts = debtAccounts(
        ref.read(debtAccountsProvider).valueOrNull ?? const [],
      );
      if (accounts.isNotEmpty || initial.accountId != null) {
        final chosen = await showDialog<({int? id})>(
          context: context,
          builder: (context) =>
              _PaidThroughDialog(debt: initial, accounts: accounts),
        );
        if (chosen == null || !mounted) return;
        through = chosen.id;
      }
    }
    final failure = await ref
        .read(debtActionsControllerProvider.notifier)
        .setPaid(
          initial,
          paidOn: initial.isOpen ? DateTime.now() : null,
          through: through,
        );
    if (!mounted) return;
    if (failure != null) return _say(failure);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = widget.initial?.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isPayment ? 'Delete this payment?' : 'Delete this debt?'),
        content: Text(
          _isPayment
              ? 'It is removed for good, and what it paid is owed again.'
              : 'It is removed for good. If it was paid back, mark it as '
                    'paid instead, and it stays in the list.',
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
        .read(debtActionsControllerProvider.notifier)
        .delete(id);
    if (!mounted) return;
    if (failure != null) return _say(failure);
    Navigator.of(context).pop();
  }

  void _say(Object? error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is Failure ? error.message : 'Something went wrong. Try again.',
      ),
    ),
  );

  Future<void> _pickIncurred() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _incurredOn,
      firstDate: DateTime(2000),
      // SaveDebt refuses a start in the future; the picker does not offer one.
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _incurredOn = picked);
  }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueOn ?? _incurredOn,
      // A due day before the start is refused; the picker does not offer one.
      firstDate: _incurredOn,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueOn = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saving = ref.watch(saveDebtControllerProvider).isLoading;
    final busy = ref.watch(debtActionsControllerProvider).isLoading;
    final initial = widget.initial;
    final day = DateFormat.yMMMd();
    final due = _dueOn;
    final dueError = _errorFor('dueOn');
    // Everyone recorded so far, for the name field to offer (FR-DBT-006).
    final everything = ref.watch(debtsProvider).valueOrNull ?? const <Debt>[];
    final names = DebtPerson.names(everything);
    final payment = _isPayment;
    final settles = payment ? _settlingAmount(everything) : null;
    final accounts = debtAccounts(
      ref.watch(debtAccountsProvider).valueOrNull ?? const [],
    );
    final paidBack = !payment && initial != null && !initial.isOpen;

    return Scaffold(
      appBar: AppBar(
        title: Text(switch ((payment, _isEditing)) {
          (true, true) => 'Edit payment',
          (true, false) => 'New payment',
          (false, true) => 'Edit debt',
          (false, false) => 'New debt',
        }),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<DebtDirection>(
              // A payment from them runs the way a debt the user owes
              // does: it takes off what they owe (FR-DBT-008).
              segments: payment
                  ? const [
                      ButtonSegment(
                        value: DebtDirection.iOwe,
                        icon: Icon(Icons.call_received),
                        label: Text('Paid me'),
                      ),
                      ButtonSegment(
                        value: DebtDirection.owedToMe,
                        icon: Icon(Icons.call_made),
                        label: Text('I paid'),
                      ),
                    ]
                  : const [
                      ButtonSegment(
                        value: DebtDirection.owedToMe,
                        icon: Icon(Icons.call_received),
                        label: Text('Owed to me'),
                      ),
                      ButtonSegment(
                        value: DebtDirection.iOwe,
                        icon: Icon(Icons.call_made),
                        label: Text('I owe'),
                      ),
                    ],
              selected: {_direction},
              onSelectionChanged: (next) =>
                  setState(() => _direction = next.single),
            ),
            const SizedBox(height: 16),
            PersonNameField(
              controller: _person,
              names: names,
              // A payment opens with its person filled in: the amount is
              // what is left to type.
              autofocus: !_isEditing && !payment,
              decoration: InputDecoration(
                labelText: switch ((payment, _direction)) {
                  (true, DebtDirection.iOwe) => 'Who paid you',
                  (true, DebtDirection.owedToMe) => 'Who you paid',
                  (false, DebtDirection.owedToMe) => 'Who owes you',
                  (false, DebtDirection.iOwe) => 'Who you owe',
                },
                border: const OutlineInputBorder(),
                errorText: _errorFor('person'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: !_isEditing && payment,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                hintText: '0.00',
                // Part or all of it: what would settle it, said, not
                // filled in (FR-DBT-008).
                helperText: settles == null
                    ? null
                    : '${formatCents(settles)} settles it',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                errorText: _errorFor('amount'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              // "Optional" under the field rather than in its label: at
              // the largest font the label has one line, and lost it.
              decoration: const InputDecoration(
                labelText: 'What for',
                helperText: 'Optional',
                border: OutlineInputBorder(),
              ),
            ),
            if (accounts.isNotEmpty || _accountId != null) ...[
              const SizedBox(height: 16),
              // Optional: without one, nothing moves, as before (E-42).
              DebtAccountField(
                label: switch ((payment, _direction)) {
                  (false, DebtDirection.owedToMe) => 'Lent from',
                  (false, DebtDirection.iOwe) => 'Borrowed into',
                  (true, DebtDirection.iOwe) => 'Paid into',
                  (true, DebtDirection.owedToMe) => 'Paid from',
                },
                helper:
                    'Optional. Its balance moves; it is not income or '
                    'spending.',
                accounts: accounts,
                value: _accountId,
                onChanged: (id) => setState(() => _accountId = id),
              ),
            ],
            if (paidBack && (accounts.isNotEmpty || _paidAccountId != null))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: DebtAccountField(
                  label: _direction == DebtDirection.owedToMe
                      ? 'Paid back into'
                      : 'Paid back from',
                  accounts: accounts,
                  value: _paidAccountId,
                  onChanged: (id) => setState(() => _paidAccountId = id),
                ),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(payment ? 'Paid on' : 'Since'),
              subtitle: Text(day.format(_incurredOn)),
              onTap: _pickIncurred,
            ),
            if (!payment)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Due by (optional)'),
                subtitle: Text(
                  due == null ? 'No due date' : day.format(due),
                  style: dueError == null
                      ? null
                      : TextStyle(color: theme.colorScheme.error),
                ),
                trailing: due == null
                    ? null
                    : IconButton(
                        tooltip: 'Remove due date',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _dueOn = null),
                      ),
                onTap: _pickDue,
              ),
            if (dueError != null)
              Text(
                dueError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(switch ((payment, _isEditing)) {
                      (_, true) => 'Save changes',
                      (true, false) => 'Save payment',
                      (false, false) => 'Add debt',
                    }),
            ),
            if (initial != null && _isEditing) ...[
              const Divider(height: 40),
              // A payment closes when the person is settled up (FR-DBT-007).
              if (!payment) ...[
                OutlinedButton.icon(
                  onPressed: busy ? null : _togglePaid,
                  icon: Icon(
                    initial.isOpen ? Icons.check_circle_outline : Icons.undo,
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  label: Text(
                    initial.isOpen ? 'Mark as paid' : 'Mark as not paid',
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextButton.icon(
                onPressed: busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                label: Text(payment ? 'Delete payment' : 'Delete debt'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Which account a debt was paid back through: the debt's own first, or
/// another, or none. FR-DBT-009.
class _PaidThroughDialog extends StatefulWidget {
  const _PaidThroughDialog({required this.debt, required this.accounts});

  final Debt debt;
  final List<AccountOption> accounts;

  @override
  State<_PaidThroughDialog> createState() => _PaidThroughDialogState();
}

class _PaidThroughDialogState extends State<_PaidThroughDialog> {
  late int? _through = widget.debt.accountId;

  @override
  Widget build(BuildContext context) {
    final owedToMe = widget.debt.direction == DebtDirection.owedToMe;
    return AlertDialog(
      scrollable: true,
      title: const Text('Mark as paid'),
      content: DebtAccountField(
        label: owedToMe ? 'Paid back into' : 'Paid back from',
        helper: 'Its balance moves back by the amount.',
        accounts: widget.accounts,
        value: _through,
        onChanged: (id) => setState(() => _through = id),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop((id: _through)),
          child: const Text('Mark as paid'),
        ),
      ],
    );
  }
}
