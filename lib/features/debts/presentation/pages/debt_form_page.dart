import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/debt.dart';
import '../../domain/usecases/save_debt.dart';
import '../providers/debt_providers.dart';

/// Recording a debt, or changing, settling or deleting one. FR-DBT-001,
/// FR-DBT-003.
///
/// One screen for both, as the account form is; [initial] being null makes
/// it a new one. Every refusal is [SaveDebt.validate]'s, shown beside the
/// field it is about once Save has been pressed.
class DebtFormPage extends ConsumerStatefulWidget {
  /// Creates the form, editing [initial] when one is given.
  const DebtFormPage({super.key, this.initial});

  /// The debt being changed, or null for a new one.
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

  /// Set once the user has tried to save, so an empty form does not
  /// complain before anything has been typed.
  bool _submitted = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _direction = initial?.direction ?? DebtDirection.owedToMe;
    _person = TextEditingController(text: initial?.person ?? '');
    _amount = TextEditingController(
      text: initial == null
          ? ''
          : formatCents(initial.amountCents, showSymbol: false),
    );
    _note = TextEditingController(text: initial?.note ?? '');
    _incurredOn = initial?.incurredOn ?? DateTime.now();
    _dueOn = initial?.dueOn;
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
    dueOn: _dueOn,
    paidOn: widget.initial?.paidOn,
  );

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
  Future<void> _togglePaid() async {
    final initial = widget.initial;
    if (initial == null) return;
    final failure = await ref
        .read(debtActionsControllerProvider.notifier)
        .setPaid(initial, paidOn: initial.isOpen ? DateTime.now() : null);
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
        title: const Text('Delete this debt?'),
        content: const Text(
          'It is removed for good. If it was paid back, mark it as paid '
          'instead, and it stays in the list.',
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

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit debt' : 'New debt')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<DebtDirection>(
              segments: const [
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
            TextField(
              controller: _person,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _direction == DebtDirection.owedToMe
                    ? 'Who owes you'
                    : 'Who you owe',
                border: const OutlineInputBorder(),
                errorText: _errorFor('person'),
              ),
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
                errorText: _errorFor('amount'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What for (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Since'),
              subtitle: Text(day.format(_incurredOn)),
              onTap: _pickIncurred,
            ),
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
                  : Text(_isEditing ? 'Save changes' : 'Add debt'),
            ),
            if (initial != null) ...[
              const Divider(height: 40),
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
              TextButton.icon(
                onPressed: busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                label: const Text('Delete debt'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
