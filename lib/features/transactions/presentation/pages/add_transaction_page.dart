import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/entry_catalog.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/amount_expression.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/transaction.dart';
import '../providers/transaction_providers.dart';
import '../widgets/amount_keypad.dart';

/// SCR-002 / SCR-003 — record an expense or an income. FR-EXP-001, FR-INC-001.
///
/// One screen for both, because they differ by a single field: which set of
/// categories is offered. Two near-identical screens would drift.
///
/// The order down the page is the order of the decision: how much, what for,
/// then the details most entries never touch. Save is reachable without
/// scrolling.
class AddTransactionPage extends ConsumerStatefulWidget {
  /// Creates the entry screen.
  const AddTransactionPage({super.key});

  @override
  ConsumerState<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  AmountExpression _amount = AmountExpression.empty();
  TransactionType _type = TransactionType.expense;
  int? _categoryId;
  int? _accountId;
  DateTime _date = DateTime.now();
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _canSave =>
      (_amount.valueCents ?? 0) > 0 &&
      _categoryId != null &&
      _accountId != null;

  Transaction _build() => Transaction(
    accountId: _accountId!,
    categoryId: _categoryId,
    amountCents: _amount.valueCents!,
    type: _type,
    date: _date,
    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
  );

  Future<void> _save() async {
    final saved = await ref
        .read(saveTransactionControllerProvider.notifier)
        .save(_build());

    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      return;
    }

    final message = failureMessage(
      ref.read(saveTransactionControllerProvider).error,
    );
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final catalog = ref.watch(entryCatalogProvider);
    final saving = ref.watch(saveTransactionControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _type == TransactionType.expense ? 'New expense' : 'New income',
        ),
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _CatalogError(message: failureMessage(error)),
        data: (data) {
          // Default to the first account rather than making the user choose
          // on a fresh install where there is only one. Sprint 3 adds the
          // selector, when there is something to select between.
          _accountId ??= data.accounts.isEmpty ? null : data.accounts.first.id;

          final categories = _type == TransactionType.expense
              ? data.expenseCategories
              : data.incomeCategories;

          return SafeArea(
            child: Column(
              children: [
                _AmountDisplay(expression: _amount, type: _type),
                _TypeToggle(
                  type: _type,
                  onChanged: (next) => setState(() {
                    _type = next;
                    // The chosen category belongs to the other list now, and
                    // an expense filed under Salary is not worth allowing.
                    _categoryId = null;
                  }),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _CategoryPicker(
                        categories: categories,
                        selectedId: _categoryId,
                        onSelected: (id) => setState(() => _categoryId = id),
                      ),
                      const SizedBox(height: 8),
                      _DateField(
                        date: _date,
                        onChanged: (next) => setState(() => _date = next),
                      ),
                      TextField(
                        controller: _note,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (data.accounts.isNotEmpty)
                        Text(
                          'Into ${data.accounts.first.name}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                AmountKeypad(
                  expression: _amount,
                  onChanged: (next) => setState(() => _amount = next),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      // Disabled rather than hidden: a button that vanishes
                      // leaves the user hunting for it, while a greyed one
                      // says "there is something still to do".
                      onPressed: _canSave && !saving ? _save : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: _type == TransactionType.expense
                            ? colors.expense
                            : colors.income,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The running total, in the colour of what it will become.
class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.expression, required this.type});

  final AmountExpression expression;
  final TransactionType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final tint = type == TransactionType.expense
        ? colors.expense
        : colors.income;

    // AddTransaction.validate is the same check the use case will run on save,
    // called here so the message appears as the user types rather than after
    // they commit — one rule, two moments.
    final value = expression.valueCents;
    final warning = value != null && value < 0
        ? 'That comes to less than nothing.'
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              expression.pendingOperator == null && value != null
                  ? formatCents(value)
                  : expression.display,
              style: theme.textTheme.displaySmall?.copyWith(
                color: tint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                warning,
                style: theme.textTheme.bodySmall?.copyWith(color: tint),
              ),
            ),
        ],
      ),
    );
  }
}

/// Expense or income. Transfers are their own screen — they have no category.
class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.type, required this.onChanged});

  final TransactionType type;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<TransactionType>(
        segments: const [
          ButtonSegment(
            value: TransactionType.expense,
            label: Text('Expense'),
            icon: Icon(Icons.arrow_upward),
          ),
          ButtonSegment(
            value: TransactionType.income,
            label: Text('Income'),
            icon: Icon(Icons.arrow_downward),
          ),
        ],
        selected: {type},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

/// The category row. FR-EXP-003.
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CategoryOption> categories;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (categories.isEmpty) {
      // E-22: a surface with nothing in it says what belongs here.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('No categories yet.', style: theme.textTheme.bodyMedium),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final category in categories)
            ChoiceChip(
              label: Text(category.name),
              selected: category.id == selectedId,
              onSelected: (_) => onSelected(category.id),
            ),
          // E-13 records an inline `+` here, creating a category without
          // leaving the entry flow. It arrives with FR-EXP-004, which is the
          // requirement that makes a category creatable at all.
        ],
      ),
    );
  }
}

/// The date, defaulting to today because that is what almost every entry is.
class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onChanged});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.calendar_today_outlined),
      title: Text(isToday ? 'Today' : '${date.year}-${date.month}-${date.day}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          // No future dates: AddTransaction rejects them anyway, and a picker
          // that offers what the validator refuses is a trap.
          lastDate: DateTime.now(),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message ?? 'Could not load your categories.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
