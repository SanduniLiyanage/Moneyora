import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ports/account_reader.dart';
import '../../../../core/ports/category_reader.dart';
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
  /// Creates the entry screen, empty for a new transaction or filled from
  /// [initial] to edit an existing one.
  ///
  /// One screen for both. An edit form that is a separate screen drifts from
  /// the entry form it is supposed to mirror, and the divergence always shows
  /// up as a field you can set when creating and not when correcting.
  const AddTransactionPage({super.key, this.initial});

  /// The transaction being edited, or null when recording a new one.
  final Transaction? initial;

  @override
  ConsumerState<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  late AmountExpression _amount;
  late TransactionType _type;
  int? _categoryId;
  int? _accountId;
  late DateTime _date;
  late final TextEditingController _note;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _amount = initial == null
        ? AmountExpression.empty()
        : AmountExpression.fromCents(initial.amountCents);
    _type = initial?.type ?? TransactionType.expense;
    _categoryId = initial?.categoryId;
    _accountId = initial?.accountId;
    _date = initial?.date ?? DateTime.now();
    _note = TextEditingController(text: initial?.note ?? '');
  }

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
    // Carried through so save() knows this is an edit rather than an entry.
    id: widget.initial?.id,
    accountId: _accountId!,
    categoryId: _categoryId,
    amountCents: _amount.valueCents!,
    type: _type,
    date: _date,
    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
  );

  /// Opens the inline category form. E-13.
  ///
  /// A category created here is selected immediately, so the flow the user
  /// started — adding this entry — never leaves the screen it was on.
  Future<void> _addCategory(BuildContext context) async {
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _QuickAddCategorySheet(isExpense: _type == TransactionType.expense),
    );
    if (id == null || !mounted) return;

    // entryCategoriesProvider is a live stream (E-27) that already carries
    // the new row through the same write CategoryListPage would see, but the
    // signal is asynchronous. Waiting for it here means the id below never
    // briefly outruns the list it needs to appear in — otherwise the build
    // below's own "category no longer exists" guard, meant for a deleted
    // category, would clear a category that only hasn't arrived yet.
    await _awaitCategory(id);
    if (!mounted) return;
    setState(() => _categoryId = id);
  }

  /// Completes once [entryCategoriesProvider] carries a category with [id].
  Future<void> _awaitCategory(int id) {
    bool hasArrived(List<CategoryOption> categories) =>
        categories.any((c) => c.id == id);

    if (hasArrived(ref.read(entryCategoriesProvider).valueOrNull ?? [])) {
      return Future.value();
    }

    final completer = Completer<void>();
    late final ProviderSubscription<AsyncValue<List<CategoryOption>>> sub;
    sub = ref.listenManual(entryCategoriesProvider, (previous, next) {
      if (hasArrived(next.valueOrNull ?? [])) {
        sub.close();
        completer.complete();
      }
    });
    return completer.future;
  }

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
    final categoriesAsync = ref.watch(entryCategoriesProvider);
    final accountsAsync = ref.watch(entryAccountsProvider);
    final saving = ref.watch(saveTransactionControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(switch ((_isEditing, _type)) {
          (true, TransactionType.income) => 'Edit income',
          (true, _) => 'Edit expense',
          (false, TransactionType.income) => 'New income',
          (false, _) => 'New expense',
        }),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _CatalogError(message: failureMessage(error)),
        data: (allCategories) => accountsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _CatalogError(message: failureMessage(error)),
          data: (accounts) {
            // Default to the first account rather than making the user choose
            // on a fresh install where there is only one. Sprint 3 adds the
            // selector, when there is something to select between.
            _accountId ??= accounts.isEmpty ? null : accounts.first.id;

            // An edit of a transaction whose category was since deleted would
            // otherwise show nothing selected and silently save a null.
            if (_categoryId != null &&
                !allCategories.any((c) => c.id == _categoryId)) {
              _categoryId = null;
            }

            final categories = allCategories
                .where((c) => c.isExpense == (_type == TransactionType.expense))
                .toList();

            return SafeArea(
              child: Column(
                children: [
                  _AmountDisplay(expression: _amount, type: _type),
                  _TypeToggle(
                    type: _type,
                    onChanged: (next) => setState(() {
                      _type = next;
                      // The chosen category belongs to the other list now,
                      // and an expense filed under Salary is not worth
                      // allowing.
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
                          onAddNew: () => _addCategory(context),
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
                        const SizedBox(height: 8),
                        _AccountPicker(
                          accounts: accounts,
                          selectedId: _accountId,
                          onSelected: (id) => setState(() => _accountId = id),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
    required this.onAddNew,
  });

  final List<CategoryOption> categories;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  /// E-13 — opens the inline form, without leaving the entry flow.
  final VoidCallback onAddNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (categories.isEmpty)
            // E-22: a surface with nothing in it says what belongs here.
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No categories yet.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in categories)
                ChoiceChip(
                  label: Text(category.name),
                  selected: category.id == selectedId,
                  onSelected: (_) => onSelected(category.id),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('New'),
                onPressed: onAddNew,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The inline category form. E-13, FR-EXP-004.
///
/// Deliberately smaller than `CategoryFormPage`: a name is all the moment of
/// discovering a category is missing needs. Icon, colour and parent are the
/// categories screen's job — SPEC_ERRATA.md's E-13 resolution keeps that
/// screen's own `+` for deliberate management, separate from this one.
class _QuickAddCategorySheet extends ConsumerStatefulWidget {
  const _QuickAddCategorySheet({required this.isExpense});

  final bool isExpense;

  @override
  ConsumerState<_QuickAddCategorySheet> createState() =>
      _QuickAddCategorySheetState();
}

class _QuickAddCategorySheetState
    extends ConsumerState<_QuickAddCategorySheet> {
  late final TextEditingController _name;

  /// Set once the user has tried to save, so the field does not complain
  /// about being empty before they have typed anything.
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _submitted = true);

    final id = await ref
        .read(quickAddCategoryControllerProvider.notifier)
        .call(name: _name.text.trim(), isExpense: widget.isExpense);

    if (!mounted) return;
    if (id != null) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saving = ref.watch(quickAddCategoryControllerProvider).isLoading;
    final error = ref.watch(quickAddCategoryControllerProvider).error;
    final message = _submitted ? failureMessage(error) : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.isExpense ? 'New expense category' : 'New income category',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'Groceries, Streaming',
              border: const OutlineInputBorder(),
              errorText: message,
            ),
            onSubmitted: (_) => saving ? null : _create(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving ? null : _create,
            child: saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add category'),
          ),
        ],
      ),
    );
  }
}

/// The account row. FR-EXP-001.
class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selectedId,
    required this.onSelected,
  });

  final List<AccountOption> accounts;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (accounts.isEmpty) {
      // E-22: a surface with nothing in it says what belongs here.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('No accounts yet.', style: theme.textTheme.bodyMedium),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final account in accounts)
            ChoiceChip(
              label: Text(account.name),
              selected: account.id == selectedId,
              onSelected: (_) => onSelected(account.id),
            ),
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
