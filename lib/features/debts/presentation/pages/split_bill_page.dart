import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/scale_down_text.dart';
import '../../domain/usecases/split_bill.dart';
import '../providers/debt_providers.dart';

/// A bill shared between the user and others, split evenly, and saved as
/// the debts it leaves. FR-DBT-004, E-44.
///
/// The total, what it was for and when; the user and everyone they shared
/// it with, by name; who paid. Each person's share is shown as it is typed,
/// adding up to the bill exactly, with who owes whom beside it. Save writes
/// the debts. What the user paid is theirs to record as an expense, as
/// any payment is: this screen says so rather than guessing the account.
class SplitBillPage extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SplitBillPage({super.key});

  @override
  ConsumerState<SplitBillPage> createState() => _SplitBillPageState();
}

class _SplitBillPageState extends ConsumerState<SplitBillPage> {
  final _total = TextEditingController();
  final _note = TextEditingController();

  /// One name field per person besides the user; one to start with.
  final List<TextEditingController> _others = [TextEditingController()];

  /// Which of the others paid, by position; null when the user did.
  int? _paidBy;
  DateTime _on = DateTime.now();

  /// Set once Save has been pressed, so a fresh form does not complain.
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _total.addListener(_changed);
    _others.first.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _total.dispose();
    _note.dispose();
    for (final field in _others) {
      field.dispose();
    }
    super.dispose();
  }

  SplitRequest get _request => SplitRequest(
    totalCents: parseToCents(_total.text) ?? 0,
    others: [for (final field in _others) field.text],
    paidBy: _paidBy,
    on: _on,
    note: _note.text,
  );

  void _addPerson() => setState(
    () => _others.add(TextEditingController()..addListener(_changed)),
  );

  void _removePerson(int index) => setState(() {
    _others.removeAt(index).dispose();
    // The payer keeps pointing at the same person, or at the user when
    // they were the one removed.
    final payer = _paidBy;
    if (payer == index) {
      _paidBy = null;
    } else if (payer != null && payer > index) {
      _paidBy = payer - 1;
    }
  });

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _on,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _on = picked);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (SplitBill.validate(_request) != null) return;

    final saved = await ref
        .read(splitBillControllerProvider.notifier)
        .split(_request);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      return;
    }
    final error = ref.read(splitBillControllerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is Failure ? error.message : 'The split could not be saved.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final saving = ref.watch(splitBillControllerProvider).isLoading;
    final request = _request;
    final problem = _submitted ? SplitBill.validate(request) : null;
    final shares = request.totalCents > 0
        ? SplitBill.shares(request.totalCents, request.people)
        : null;
    String nameOf(int i) => switch (_others[i].text.trim()) {
      '' => 'Person ${i + 2}',
      final name => name,
    };
    final payerName = switch (_paidBy) {
      final i? => nameOf(i),
      null => 'You',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Split a bill')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _total,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Total',
                hintText: '0.00',
                border: const OutlineInputBorder(),
                errorText: problem?.field == 'total' ? problem!.message : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What for (optional)',
                hintText: 'Dinner',
                border: OutlineInputBorder(),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Paid on'),
              subtitle: Text(DateFormat.yMMMd().format(_on)),
              onTap: _pickDay,
            ),
            const SizedBox(height: 8),
            Text(
              'Shared by ${request.people}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            _ShareRow(
              name: 'You',
              share: shares?.first,
              paid: _paidBy == null,
              trailing: null,
            ),
            for (final (i, field) in _others.indexed)
              _ShareRow(
                key: ObjectKey(field),
                name: null,
                field: field,
                hint: 'Person ${i + 2}',
                share: shares?[i + 1],
                paid: _paidBy == i,
                trailing: _others.length > 1
                    ? IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close),
                        onPressed: () => _removePerson(i),
                      )
                    : null,
              ),
            if (request.people < SplitBill.maxPeople)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _addPerson,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add a person'),
                ),
              ),
            if (problem != null && problem.field == 'people')
              Text(
                problem.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              // Remade when a person is added or removed: the field keeps
              // its own value, which would otherwise point at someone gone.
              key: ValueKey((_others.length, _paidBy)),
              initialValue: _paidBy,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Who paid',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('You')),
                for (var i = 0; i < _others.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(nameOf(i), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (next) => setState(() => _paidBy = next),
            ),
            const SizedBox(height: 12),
            if (shares != null)
              Text(
                _paidBy == null
                    ? 'Each of the others will owe you their share.'
                    : 'You will owe $payerName '
                          '${formatCents(shares.first)}.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _paidBy == null ? colors.income : colors.expense,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'This records who owes what. What you paid yourself, record '
              'as an expense with − on home.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
                  : const Text('Save as debts'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One person and their share: the user by name, everyone else in a field
/// to name them.
class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.name,
    required this.share,
    required this.paid,
    required this.trailing,
    this.field,
    this.hint,
    super.key,
  });

  /// The user's row's label; null for a row with a [field].
  final String? name;
  final TextEditingController? field;
  final String? hint;
  final int? share;

  /// Whether this person paid the bill.
  final bool paid;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: label != null
                ? Text(label, style: theme.textTheme.bodyLarge)
                : TextField(
                    controller: field,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(hintText: hint, isDense: true),
                  ),
          ),
          const SizedBox(width: 12),
          // Gives way at the largest font on a small phone: the share
          // shrinks rather than pushing the name off the row.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ScaleDownText(
                  share == null ? '—' : formatCents(share!),
                  style: theme.textTheme.titleMedium,
                ),
                if (paid) Text('paid', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
