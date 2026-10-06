import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Left, Right;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/ports/account_reader.dart';
import '../../../../core/ports/category_reader.dart';
import '../../../../core/ports/expense_photos.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/amount_expression.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../injection.dart';
import '../../domain/entities/recurring_rule.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/usecases/create_recurring_rule.dart';
import '../../domain/usecases/discard_unused_photos.dart';
import '../providers/transaction_providers.dart';
import '../widgets/amount_keypad.dart';
import '../widgets/recurrence_labels.dart';

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
  const AddTransactionPage({
    super.key,
    this.initial,
    this.type = TransactionType.expense,
  });

  /// The transaction being edited, or null when recording a new one.
  final Transaction? initial;

  /// What a new entry starts as: home's − opens an expense and its + an
  /// income. Ignored when editing, where the row says what it is.
  final TransactionType type;

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

  /// E-13's recurring toggle, and the schedule it opens. FR-EXP-008,
  /// FR-INC-004. Offered on a new entry only: an edit is a row that already
  /// exists, and a rule is created with its first entry.
  bool _repeats = false;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  late final TextEditingController _interval;
  DateTime? _endDate;

  /// Whether the keypad is showing.
  ///
  /// On a short phone the keypad and Save leave the details list a sliver:
  /// the second row of category chips peeks out beneath the first, and the
  /// date and the Repeat choices are out of reach. So the keypad folds away
  /// when the user reaches for the details — dragging the list, or turning
  /// Repeat on — and comes back from the amount, where the number it types
  /// is shown.
  bool _keypadOpen = true;

  /// The Repeat section, so turning it on can bring it into view.
  final _repeatKey = GlobalKey();

  /// The photo on this expense, if any. FR-EXP-009.
  String? _photoPath;

  /// Photos kept in the vault while this form was open. Each is sealed the
  /// moment it is chosen, so the ones the saved row does not name — or all
  /// of them, if nothing is saved — are discarded when the form closes.
  final Set<String> _keptHere = {};
  bool _saved = false;

  /// Read up front: [dispose] cannot reach the container.
  late final DiscardUnusedPhotos _discardUnused;

  bool get _isEditing => widget.initial != null;

  void _toggleRepeat() {
    setState(() {
      _repeats = !_repeats;
      if (_repeats) _keypadOpen = false;
    });
    if (!_repeats) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final section = _repeatKey.currentContext;
      if (section != null && section.mounted) {
        Scrollable.ensureVisible(
          section,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  /// Folds the keypad away when the user drags the details list.
  ///
  /// Only a drag: a scroll with no drag behind it is the framework bringing
  /// something into view, which is no sign the user is done typing.
  bool _onDetailsScroll(ScrollStartNotification notification) {
    if (notification.dragDetails != null && _keypadOpen) {
      setState(() => _keypadOpen = false);
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _amount = initial == null
        ? AmountExpression.empty()
        : AmountExpression.fromCents(initial.amountCents);
    _type = initial?.type ?? widget.type;
    _categoryId = initial?.categoryId;
    _accountId = initial?.accountId;
    _date = initial?.date ?? DateTime.now();
    _note = TextEditingController(text: initial?.note ?? '');
    _interval = TextEditingController(text: '7');
    _photoPath = initial?.receiptImagePath;
    _discardUnused = ref.read(discardUnusedPhotosProvider);
  }

  @override
  void dispose() {
    // Backed out: nothing names the photos taken here.
    if (!_saved && _keptHere.isNotEmpty) {
      unawaited(_discardUnused(PhotoCleanup(keptHere: {..._keptHere})));
    }
    _note.dispose();
    _interval.dispose();
    super.dispose();
  }

  /// The entry's own fields are complete.
  bool get _entryComplete =>
      (_amount.valueCents ?? 0) > 0 &&
      _categoryId != null &&
      _accountId != null;

  bool get _canSave => _entryComplete && (!_repeats || _repeatProblem == null);

  RecurringRuleRequest _request() => RecurringRuleRequest(
    first: _build(),
    frequency: _frequency,
    intervalDays: int.tryParse(_interval.text.trim()),
    endDate: _endDate,
  );

  /// Why the schedule cannot be saved, in `CreateRecurringRule`'s own
  /// words, or null. The same check the use case runs on save, called as
  /// the user changes the schedule — a monthly start past the 28th is said
  /// here, not discovered on tapping Save. Only once the entry is complete,
  /// so the amount's and category's own gaps are not repeated under the
  /// schedule.
  String? get _repeatProblem {
    if (!_repeats || !_entryComplete) return null;
    return CreateRecurringRule.validate(_request())?.message;
  }

  /// The row this screen would write.
  ///
  /// An edit starts from the row being edited, not from a blank one: the
  /// update writes every column, so anything this form does not show — the
  /// time, split parts, the receipt link and photo, the recurring link —
  /// would otherwise be written back as empty. Editing a split's category
  /// used to delete its parts that way.
  Transaction _build() {
    final initial = widget.initial;
    return Transaction(
      // Carried through so save() knows this is an edit rather than an entry.
      id: initial?.id,
      accountId: _accountId!,
      categoryId: _categoryId,
      amountCents: _amount.valueCents!,
      type: _type,
      date: _date,
      time: initial?.time,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      splits: initial?.splits ?? const [],
      receiptScanId: initial?.receiptScanId,
      // A photo belongs on an expense (FR-EXP-009); the row is not offered
      // on an income, so switching to one leaves the photo behind.
      receiptImagePath: _type == TransactionType.expense ? _photoPath : null,
      recurringRuleId: initial?.recurringRuleId,
      isRecurring: initial?.isRecurring ?? false,
    );
  }

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

  /// Asks where from, then keeps the photo. FR-EXP-009.
  Future<void> _attachPhoto() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from your photos'),
              onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final result = await ref.read(attachExpensePhotoProvider)(source);
    if (!mounted) return;
    switch (result) {
      case Left(value: final failure):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      case Right(value: final path?):
        setState(() {
          _photoPath = path;
          _keptHere.add(path);
        });
      case Right():
      // Backed out of the picker: nothing to keep.
    }
  }

  Future<void> _save() async {
    final controller = ref.read(saveTransactionControllerProvider.notifier);
    final row = _build();
    final saved = _repeats
        ? await controller.saveRepeating(_request())
        : await controller.save(row);

    if (saved) {
      // Only now: a failed save must not lose the photo it was keeping.
      _saved = true;
      unawaited(
        _discardUnused(
          PhotoCleanup(before: widget.initial, after: row, keptHere: _keptHere),
        ),
      );
    }
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
        actions: [
          // FR-RCP-001: the scanner from the add-expense flow as well as
          // the main screen. A new expense only — a receipt is never an
          // income, and an edit is a row that already exists.
          if (!_isEditing && _type == TransactionType.expense)
            IconButton(
              tooltip: 'Scan Receipt',
              icon: const Icon(Icons.document_scanner_outlined),
              onPressed: () => context.push(Routes.scanReceipt),
            ),
        ],
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
                  _AmountDisplay(
                    expression: _amount,
                    type: _type,
                    keypadOpen: _keypadOpen,
                    onToggleKeypad: () =>
                        setState(() => _keypadOpen = !_keypadOpen),
                    // E-13's recurring toggle, labelled, in the space beside
                    // the amount. It was a bare icon in the app bar, where it
                    // looked like the transfer arrows and was not found; here
                    // it costs no height on a small phone. A new entry only —
                    // see _repeats.
                    repeat: _isEditing
                        ? null
                        : FilterChip(
                            tooltip: _repeats ? 'Stop repeating' : 'Repeat',
                            avatar: const Icon(Icons.repeat),
                            label: const Text('Repeat'),
                            selected: _repeats,
                            showCheckmark: false,
                            onSelected: (_) => _toggleRepeat(),
                          ),
                  ),
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
                    child: NotificationListener<ScrollStartNotification>(
                      onNotification: _onDetailsScroll,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          _CategoryPicker(
                            categories: categories,
                            selectedId: _categoryId,
                            onSelected: (id) =>
                                setState(() => _categoryId = id),
                            onAddNew: () => _addCategory(context),
                          ),
                          const SizedBox(height: 8),
                          _DateField(
                            date: _date,
                            onChanged: (next) => setState(() => _date = next),
                          ),
                          if (_repeats)
                            _RepeatSection(
                              key: _repeatKey,
                              frequency: _frequency,
                              onFrequency: (next) =>
                                  setState(() => _frequency = next),
                              interval: _interval,
                              onIntervalChanged: () => setState(() {}),
                              startDate: _date,
                              endDate: _endDate,
                              onEndDate: (next) =>
                                  setState(() => _endDate = next),
                              problem: _repeatProblem,
                              // From the schedule alone: the entry may not
                              // have an amount yet.
                              summary: describeRecurrence(
                                RecurringRule.startingOn(
                                  _date,
                                  frequency: _frequency,
                                  intervalDays: int.tryParse(
                                    _interval.text.trim(),
                                  ),
                                  endDate: _endDate,
                                ),
                              ),
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
                          const SizedBox(height: 8),
                          if (_type == TransactionType.expense)
                            _PhotoField(
                              path: _photoPath,
                              // A scan's photo is the scan record's, shared
                              // by every expense the receipt produced: it is
                              // shown here, and changed nowhere.
                              fromScan: widget.initial?.receiptScanId != null,
                              onAttach: _attachPhoto,
                              onRemove: () => setState(() => _photoPath = null),
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  if (_keypadOpen)
                    AmountKeypad(
                      // Under 720dp tall — a 640dp phone left the details a
                      // 40dp sliver at 64 — keys drop to the 48dp minimum
                      // target, which buys two full rows of categories.
                      keyHeight: MediaQuery.sizeOf(context).height < 720
                          ? 48
                          : 64,
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

/// The photo on an expense: attach, view, replace, remove. FR-EXP-009.
class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.path,
    required this.fromScan,
    required this.onAttach,
    required this.onRemove,
  });

  final String? path;
  final bool fromScan;
  final VoidCallback onAttach;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    if (path == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onAttach,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Attach a photo'),
        ),
      );
    }

    return Row(
      children: [
        _PhotoThumbnail(
          path: path,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => _PhotoPage(path: path)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(fromScan ? 'Photo from the receipt scan' : 'Photo'),
        ),
        if (!fromScan) ...[
          IconButton(
            tooltip: 'Replace photo',
            onPressed: onAttach,
            icon: const Icon(Icons.add_a_photo_outlined),
          ),
          IconButton(
            tooltip: 'Remove photo',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ],
    );
  }
}

/// A small crop of the photo, decrypted through [expensePhotoProvider].
class _PhotoThumbnail extends ConsumerWidget {
  const _PhotoThumbnail({required this.path, required this.onTap});

  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final placeholder = theme.colorScheme.surfaceContainerHighest;
    return Semantics(
      button: true,
      label: 'View photo',
      child: InkWell(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
            dimension: 56,
            child: switch (ref.watch(expensePhotoProvider(path))) {
              AsyncData(value: final bytes?) => Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
              AsyncData() => ColoredBox(
                color: placeholder,
                child: const Icon(Icons.image_not_supported_outlined),
              ),
              AsyncError() => ColoredBox(
                color: placeholder,
                child: const Icon(Icons.lock_outline),
              ),
              _ => ColoredBox(color: placeholder),
            },
          ),
        ),
      ),
    );
  }
}

/// The photo, full size, pinch-to-zoom.
class _PhotoPage extends ConsumerWidget {
  const _PhotoPage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Photo')),
    body: switch (ref.watch(expensePhotoProvider(path))) {
      AsyncData(value: final bytes?) => InteractiveViewer(
        maxScale: 5,
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
      ),
      AsyncData() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'The photo is no longer on this phone.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      AsyncError(:final error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            failureMessage(error) ?? 'The photo could not be opened.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    },
  );
}

/// The running total, in the colour of what it will become.
class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({
    required this.expression,
    required this.type,
    required this.keypadOpen,
    required this.onToggleKeypad,
    this.repeat,
  });

  final AmountExpression expression;
  final TransactionType type;

  /// Whether the keypad below is showing, and the way to fold or open it.
  final bool keypadOpen;
  final VoidCallback onToggleKeypad;

  /// The Repeat toggle, beside the keypad's; null when editing.
  final Widget? repeat;

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

    return InkWell(
      // The number is where the keypad types, so it is where the keypad is
      // brought back from.
      onTap: keypadOpen ? null : onToggleKeypad,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(4, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: keypadOpen ? 'Hide keypad' : 'Show keypad',
                  icon: Icon(
                    keypadOpen ? Icons.keyboard_hide_outlined : Icons.dialpad,
                  ),
                  onPressed: onToggleKeypad,
                ),
                ?repeat,
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
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
                ),
              ],
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
            icon: Icon(Icons.arrow_downward),
          ),
          ButtonSegment(
            value: TransactionType.income,
            label: Text('Income'),
            icon: Icon(Icons.arrow_upward),
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

/// How often the entry repeats, and until when. E-13, FR-EXP-008,
/// FR-INC-004.
///
/// The entry's date above is the series' start. Every option FR-EXP-008
/// lists is a chip; the custom interval is a field that appears with its
/// chip. Below them, either the reason the schedule cannot be saved or what
/// it will do, in the words the rules list uses for it.
class _RepeatSection extends StatelessWidget {
  const _RepeatSection({
    required this.frequency,
    super.key,
    required this.onFrequency,
    required this.interval,
    required this.onIntervalChanged,
    required this.startDate,
    required this.endDate,
    required this.onEndDate,
    required this.problem,
    required this.summary,
  });

  final RecurrenceFrequency frequency;
  final ValueChanged<RecurrenceFrequency> onFrequency;
  final TextEditingController interval;
  final VoidCallback onIntervalChanged;
  final DateTime startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime?> onEndDate;
  final String? problem;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = endDate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Repeats', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in RecurrenceFrequency.values)
                ChoiceChip(
                  label: Text(frequencyLabel(option)),
                  selected: option == frequency,
                  onSelected: (_) => onFrequency(option),
                ),
            ],
          ),
          if (frequency == RecurrenceFrequency.customDays)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                controller: interval,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Every how many days',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => onIntervalChanged(),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_busy_outlined),
            title: Text(
              end == null
                  ? 'No end date'
                  : 'Ends ${DateFormat.yMMMd().format(end)}',
            ),
            trailing: end == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    tooltip: 'Remove end date',
                    icon: const Icon(Icons.close),
                    onPressed: () => onEndDate(null),
                  ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: end ?? startDate,
                // An end before the start is refused by the use case; a
                // picker that offers one is a trap.
                firstDate: startDate,
                lastDate: DateTime(2100),
              );
              if (picked != null) onEndDate(picked);
            },
          ),
          Text(
            problem ?? summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: problem == null ? null : theme.colorScheme.error,
            ),
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
