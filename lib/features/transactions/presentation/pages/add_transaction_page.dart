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
import '../../../../core/theme/category_palette.dart';
import '../../../../core/utils/amount_expression.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/account_icons.dart';
import '../../../../core/widgets/category_icons.dart';
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
/// One question at a time, top to bottom: the date, the amount in a bar
/// with the account it comes from, a note, the keypad, and CHOOSE CATEGORY
/// at the bottom. Choosing a category fills it in, and **Save** beside it
/// records the entry and returns to where it was opened from. Tapping the
/// category used to record at once; a tester tapped the wrong one and had
/// a row to undo, so the last step is a button that says what it does.
/// Repeat, a photo and the receipt scanner are the small icons beside the
/// note.
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
    this.accountId,
  });

  /// The transaction being edited, or null when recording a new one.
  final Transaction? initial;

  /// What a new entry starts as: home's − opens an expense and its + an
  /// income. Ignored when editing, where the row says what it is.
  final TransactionType type;

  /// The account a new entry starts in: the one chosen in home's left
  /// panel, or the one the list is showing. Ignored when editing, and when
  /// it is no longer among the accounts offered (archived since), where the
  /// first account is the default as before.
  final int? accountId;

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
  final _noteFocus = FocusNode();

  /// E-13's recurring toggle, and the schedule it opens. FR-EXP-008,
  /// FR-INC-004. Offered on a new entry only: an edit is a row that already
  /// exists, and a rule is created with its first entry.
  bool _repeats = false;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  late final TextEditingController _interval;
  DateTime? _endDate;

  /// Whether the keypad is showing.
  ///
  /// On a short phone the keypad and CHOOSE CATEGORY leave the details a
  /// sliver: the Repeat choices and a photo are out of reach. So the keypad
  /// folds away when the user reaches for the details — dragging them,
  /// typing a note, or turning Repeat on — and comes back from the amount,
  /// where the number it types is shown.
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

  bool get _isExpense => _type == TransactionType.expense;

  void _toggleRepeat() {
    setState(() {
      _repeats = !_repeats;
      if (_repeats) _keypadOpen = false;
    });
    if (!_repeats) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final section = _repeatKey.currentContext;
      if (section != null && section.mounted) {
        // Only as far as its end: the note and the icons beside it stay
        // in view where there is room for both.
        Scrollable.ensureVisible(
          section,
          duration: const Duration(milliseconds: 200),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  /// Folds the keypad away when the user drags the details.
  ///
  /// Only a drag: a scroll with no drag behind it is the framework bringing
  /// something into view, which is no sign the user is done typing.
  bool _onDetailsScroll(ScrollStartNotification notification) {
    if (notification.dragDetails != null && _keypadOpen) {
      setState(() => _keypadOpen = false);
    }
    return false;
  }

  /// The system keyboard and the keypad do not both fit: typing a note
  /// folds the keypad, and the amount brings it back.
  void _onNoteFocus() {
    if (_noteFocus.hasFocus && _keypadOpen) {
      setState(() => _keypadOpen = false);
    }
  }

  void _openKeypad() {
    _noteFocus.unfocus();
    if (!_keypadOpen) setState(() => _keypadOpen = true);
  }

  /// Expense to income and back: the icon at the top right. The chosen
  /// category belongs to the other list, and an expense filed under Salary
  /// is not worth allowing, so it is cleared.
  void _switchType() => setState(() {
    _type = _isExpense ? TransactionType.income : TransactionType.expense;
    _categoryId = null;
  });

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
    _noteFocus.addListener(_onNoteFocus);
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
    _noteFocus.dispose();
    _interval.dispose();
    super.dispose();
  }

  /// There is an amount to record, and an account to record it in: the
  /// category is the step CHOOSE CATEGORY takes.
  bool get _canChoose => (_amount.valueCents ?? 0) > 0 && _accountId != null;

  /// Everything Save needs: an amount, an account and a category.
  bool get _canSave => _canChoose && _categoryId != null;

  RecurringRuleRequest _request({int? categoryId}) => RecurringRuleRequest(
    first: _build(categoryId: categoryId),
    frequency: _frequency,
    intervalDays: int.tryParse(_interval.text.trim()),
    endDate: _endDate,
  );

  /// Why the schedule cannot be saved, in `CreateRecurringRule`'s own
  /// words, or null. The same check the use case runs on save, called as
  /// the user changes the schedule — a monthly start past the 28th is said
  /// here, not discovered after choosing a category. Until one is chosen it
  /// is checked against [categoryId], since the schedule's rules do not
  /// depend on which.
  String? _repeatProblem({int? categoryId}) {
    if (!_repeats || !_canChoose) return null;
    final id = _categoryId ?? categoryId;
    if (id == null) return null;
    return CreateRecurringRule.validate(_request(categoryId: id))?.message;
  }

  /// The row this screen would write, with [categoryId] in place of the
  /// chosen category when one is given.
  ///
  /// An edit starts from the row being edited, not from a blank one: the
  /// update writes every column, so anything this form does not show — the
  /// time, split parts, the receipt link and photo, the recurring link —
  /// would otherwise be written back as empty. Editing a split's category
  /// used to delete its parts that way.
  Transaction _build({int? categoryId}) {
    final initial = widget.initial;
    return Transaction(
      // Carried through so save() knows this is an edit rather than an entry.
      id: initial?.id,
      accountId: _accountId!,
      categoryId: categoryId ?? _categoryId,
      amountCents: _amount.valueCents!,
      type: _type,
      date: _date,
      time: initial?.time,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      splits: initial?.splits ?? const [],
      receiptScanId: initial?.receiptScanId,
      // A photo belongs on an expense (FR-EXP-009); the icon is not offered
      // on an income, so switching to one leaves the photo behind.
      receiptImagePath: _isExpense ? _photoPath : null,
      recurringRuleId: initial?.recurringRuleId,
      isRecurring: initial?.isRecurring ?? false,
    );
  }

  /// CHOOSE CATEGORY, or the chosen one to change it: the grid, and the
  /// category tapped there is filled in. Save records. FR-EXP-001,
  /// FR-INC-001.
  Future<void> _chooseCategory() async {
    // A sum still open — "1,250 + 340" — is finished first, as = would.
    setState(() => _amount = _amount.evaluated());
    if (!_canChoose) return;
    _noteFocus.unfocus();

    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) =>
            _CategoryGrid(isExpense: _isExpense, selectedId: _categoryId),
      ),
    );
    if (id == null || !mounted) return;

    // A category made from the grid arrives on the live list a moment
    // after its id; waiting for it means the build's "category no longer
    // exists" guard never clears one that only has not arrived yet.
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

  /// The account the amount comes from or goes to: the icon at the left of
  /// the amount. FR-EXP-001.
  Future<void> _chooseAccount(List<AccountOption> accounts) async {
    final id = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final account in accounts)
              ListTile(
                leading: Icon(accountIconFor(account.icon)),
                title: Text(account.name),
                subtitle: Text(
                  formatCents(
                    account.balanceCents,
                    currency: CurrencyFormat.forCode(account.currency),
                  ),
                ),
                selected: account.id == _accountId,
                trailing: account.id == _accountId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(account.id),
              ),
          ],
        ),
      ),
    );
    if (id != null && mounted) setState(() => _accountId = id);
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
    // A sum still open — "1,250 + 340" — is finished first, as = would.
    setState(() => _amount = _amount.evaluated());
    if (!_canSave) return;
    _noteFocus.unfocus();
    final problem = _repeatProblem();
    if (problem != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

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
    final tint = _isExpense ? colors.expense : colors.income;
    final onBar = theme.appBarTheme.foregroundColor ?? colors.onBrand;

    return Scaffold(
      appBar: AppBar(
        // Cancel in words rather than an arrow: what it does to the
        // half-typed entry is the thing worth saying.
        leadingWidth: 96,
        leading: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          style: TextButton.styleFrom(foregroundColor: onBar),
          child: const Text('Cancel'),
        ),
        centerTitle: true,
        title: Text(switch ((_isEditing, _type)) {
          (true, TransactionType.income) => 'Edit income',
          (true, _) => 'Edit expense',
          (false, TransactionType.income) => 'New income',
          (false, _) => 'New expense',
        }),
        actions: [
          // Back to the list with the answer, which deletes the row with its
          // undo window (E-23): a mistaken tap is one more tap to take back.
          if (_isEditing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          // Up for income, down for an expense: the way each moves the
          // balance, as the list's arrows say. Transfers are their own
          // screen — they have no category.
          IconButton(
            tooltip: _isExpense ? 'Switch to income' : 'Switch to expense',
            icon: const Icon(Icons.swap_vert),
            onPressed: _switchType,
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
            // The account the user is looking at, else the first one rather
            // than making them choose on a fresh install where there is only
            // one. Defaulting to the first alone filed entries meant for a
            // new account under the old one.
            _accountId ??=
                accounts
                    .where((a) => a.id == widget.accountId)
                    .firstOrNull
                    ?.id ??
                accounts.firstOrNull?.id;
            final account = accounts
                .where((a) => a.id == _accountId)
                .firstOrNull;

            // The schedule's own refusal, if it has one, checked against the
            // first category of the list until one is chosen. While there
            // is one, CHOOSE CATEGORY waits: the Repeat section says why.
            final repeatProblem = _repeatProblem(
              categoryId: allCategories
                  .where((c) => c.isExpense == _isExpense)
                  .firstOrNull
                  ?.id,
            );

            // An edit of a transaction whose category was since deleted would
            // otherwise show it chosen and silently save a dangling id.
            if (_categoryId != null &&
                !allCategories.any((c) => c.id == _categoryId)) {
              _categoryId = null;
            }
            final category = allCategories
                .where((c) => c.id == _categoryId)
                .firstOrNull;

            return SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: NotificationListener<ScrollStartNotification>(
                      onNotification: _onDetailsScroll,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        children: [
                          Center(
                            child: _DateButton(
                              date: _date,
                              onChanged: (next) => setState(() => _date = next),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _AmountBar(
                            expression: _amount,
                            tint: tint,
                            account: account,
                            onAccount: accounts.length < 2
                                ? null
                                : () => _chooseAccount(accounts),
                            onBackspace: () =>
                                setState(() => _amount = _amount.backspace()),
                            onTap: _openKeypad,
                          ),
                          if ((_amount.valueCents ?? 0) < 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'That comes to less than nothing.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tint,
                                ),
                              ),
                            ),
                          if (accounts.isEmpty)
                            // E-22: a surface with nothing in it says what
                            // belongs here.
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'No accounts yet.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          const SizedBox(height: 8),
                          _NoteRow(
                            controller: _note,
                            focusNode: _noteFocus,
                            // A new entry only — see _repeats.
                            repeat: _isEditing
                                ? null
                                : IconButton(
                                    tooltip: _repeats
                                        ? 'Stop repeating'
                                        : 'Repeat',
                                    isSelected: _repeats,
                                    icon: const Icon(Icons.repeat),
                                    selectedIcon: Icon(
                                      Icons.repeat_on,
                                      color: tint,
                                    ),
                                    onPressed: _toggleRepeat,
                                  ),
                            // A photo belongs on an expense. Once there is
                            // one it is shown below, with its own replace
                            // and remove; a scan's is the scan record's, and
                            // changed nowhere.
                            photo:
                                _isExpense &&
                                    _photoPath == null &&
                                    widget.initial?.receiptScanId == null
                                ? IconButton(
                                    tooltip: 'Attach a photo',
                                    icon: const Icon(
                                      Icons.add_a_photo_outlined,
                                    ),
                                    onPressed: _attachPhoto,
                                  )
                                : null,
                            // FR-RCP-001: the scanner from the add-expense
                            // flow as well as the menu. A new expense only —
                            // a receipt is never an income, and an edit is a
                            // row that already exists.
                            scan: !_isEditing && _isExpense
                                ? IconButton(
                                    tooltip: 'Scan Receipt',
                                    icon: const Icon(
                                      Icons.document_scanner_outlined,
                                    ),
                                    onPressed: () =>
                                        context.push(Routes.scanReceipt),
                                  )
                                : null,
                          ),
                          if (_isExpense && _photoPath != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _PhotoField(
                                path: _photoPath!,
                                fromScan: widget.initial?.receiptScanId != null,
                                onAttach: _attachPhoto,
                                onRemove: () =>
                                    setState(() => _photoPath = null),
                              ),
                            ),
                          if (_repeats)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _RepeatSection(
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
                                problem: repeatProblem,
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
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_keypadOpen)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: AmountKeypad(
                        // Under 720dp tall the keys drop to the 48dp minimum
                        // target, which keeps the date, the amount and the
                        // note in view on a 640dp phone.
                        keyHeight: MediaQuery.sizeOf(context).height < 720
                            ? 48
                            : 60,
                        accent: tint,
                        expression: _amount,
                        onChanged: (next) => setState(() => _amount = next),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                    child: category == null
                        ? SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              // Disabled rather than hidden until there is
                              // an amount: a button that vanishes leaves the
                              // user hunting for it, while a greyed one says
                              // "there is something still to do".
                              onPressed:
                                  _canChoose && repeatProblem == null && !saving
                                  ? _chooseCategory
                                  : null,
                              style: _outlined(
                                theme,
                                enabled: _canChoose && repeatProblem == null,
                                tint: tint,
                              ),
                              child: const Text(
                                'CHOOSE CATEGORY',
                                style: TextStyle(letterSpacing: 0.8),
                              ),
                            ),
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Tooltip(
                                  message: 'Change category',
                                  child: OutlinedButton.icon(
                                    onPressed: saving ? null : _chooseCategory,
                                    style: _outlined(
                                      theme,
                                      enabled: true,
                                      tint: tint,
                                    ),
                                    icon: Icon(
                                      categoryIconFor(category.icon),
                                      color: categoryColorFor(
                                        category.colorHex,
                                        theme.brightness,
                                      ),
                                    ),
                                    label: Text(
                                      category.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  onPressed:
                                      _canSave &&
                                          repeatProblem == null &&
                                          !saving
                                      ? _save
                                      : null,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                    backgroundColor: tint,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  child: saving
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'SAVE',
                                          style: TextStyle(letterSpacing: 0.8),
                                        ),
                                ),
                              ),
                            ],
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

/// The outline of the category button: in the entry's colour once it can
/// be pressed, grey until then.
ButtonStyle _outlined(
  ThemeData theme, {
  required bool enabled,
  required Color tint,
}) => OutlinedButton.styleFrom(
  minimumSize: const Size.fromHeight(52),
  foregroundColor: theme.colorScheme.onSurface,
  side: BorderSide(
    color: enabled ? tint.withValues(alpha: 0.6) : theme.disabledColor,
  ),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
);

/// The photo on an expense: view, replace, remove. FR-EXP-009. Attaching
/// the first is the camera icon beside the note.
class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.path,
    required this.fromScan,
    required this.onAttach,
    required this.onRemove,
  });

  final String path;
  final bool fromScan;
  final VoidCallback onAttach;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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

/// The date, at the top, defaulting to today because that is what almost
/// every entry is.
class _DateButton extends StatelessWidget {
  const _DateButton({required this.date, required this.onChanged});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    // The year only when it is not this one: "Tuesday, 6 October" is the
    // whole answer almost every time.
    final format = date.year == now.year
        ? DateFormat('EEEE, d MMMM')
        : DateFormat('EEEE, d MMMM y');

    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurface),
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text(format.format(date)),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          // No future dates: AddTransaction rejects them anyway, and a picker
          // that offers what the validator refuses is a trap.
          lastDate: now,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// The amount, in a bar the colour of what it will become, with the account
/// it comes from at its left and backspace at its right.
class _AmountBar extends StatelessWidget {
  const _AmountBar({
    required this.expression,
    required this.tint,
    required this.account,
    required this.onAccount,
    required this.onBackspace,
    required this.onTap,
  });

  final AmountExpression expression;
  final Color tint;

  /// Where the money comes from or goes to; null while there is none.
  final AccountOption? account;

  /// Opens the account choice; null when there is nothing to choose between.
  final VoidCallback? onAccount;
  final VoidCallback onBackspace;

  /// Brings the keypad back when it has folded away.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onTint = Colors.white;
    final value = expression.valueCents;
    final account = this.account;

    return Material(
      color: tint,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 76,
          child: Row(
            children: [
              Tooltip(
                message: 'Account: ${account?.name ?? 'none'}',
                child: InkWell(
                  onTap: onAccount,
                  child: SizedBox(
                    width: 68,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          accountIconFor(account?.icon ?? ''),
                          color: onTint,
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            account?.currency ?? '',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: onTint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 52,
                color: onTint.withValues(alpha: 0.5),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      expression.pendingOperator == null && value != null
                          ? formatCents(value)
                          : expression.display,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: onTint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Backspace',
                color: onTint,
                icon: const Icon(Icons.backspace_outlined),
                onPressed: onBackspace,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Add note", with the small extras beside it: Repeat, a photo, the
/// receipt scanner. Each is null where it does not apply.
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.controller,
    required this.focusNode,
    required this.repeat,
    required this.photo,
    required this.scan,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget? repeat;
  final Widget? photo;
  final Widget? scan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Add note',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
          ),
        ),
        ?repeat,
        ?photo,
        ?scan,
      ],
    );
  }
}

/// The categories of an expense or an income, as a grid of their icons.
/// Tapping one answers it; the entry screen shows it beside Save.
/// FR-EXP-003, FR-INC-002.
class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid({required this.isExpense, required this.selectedId});

  final bool isExpense;

  /// Marked, when an edit already has one.
  final int? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = (ref.watch(entryCategoriesProvider).valueOrNull ?? [])
        .where((c) => c.isExpense == isExpense)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Choose category')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => GridView.count(
            padding: const EdgeInsets.all(12),
            // Four across a phone, more on anything wider; never so narrow
            // a name cannot fit under its icon.
            crossAxisCount: (constraints.maxWidth / 88).floor().clamp(3, 8),
            mainAxisSpacing: 8,
            crossAxisSpacing: 4,
            childAspectRatio: 0.78,
            children: [
              for (final category in categories)
                _CategoryTile(
                  category: category,
                  selected: category.id == selectedId,
                  onTap: () => Navigator.of(context).pop(category.id),
                ),
              // E-13: a missing category is made here, without leaving the
              // entry, and chosen at once.
              _NewCategoryTile(isExpense: isExpense),
            ],
          ),
        ),
      ),
      bottomNavigationBar: categories.isEmpty
          // E-22: a surface with nothing in it says what belongs here.
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No categories yet. Tap New to make one.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            )
          : null,
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final CategoryOption category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = categoryColorFor(category.colorHex, theme.brightness);
    final onColor = color.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          const SizedBox(height: 4),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: theme.colorScheme.onSurface, width: 3)
                  : null,
            ),
            child: Icon(categoryIconFor(category.icon), color: onColor),
          ),
          const SizedBox(height: 6),
          Expanded(
            // One word too long for the tile shrinks rather than breaking
            // mid-word ("Communicatio / ns"); several wrap between words.
            child: category.name.trim().contains(' ')
                ? Text(
                    category.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  )
                : Align(
                    alignment: Alignment.topCenter,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        category.name,
                        maxLines: 1,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NewCategoryTile extends StatelessWidget {
  const _NewCategoryTile({required this.isExpense});

  final bool isExpense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final id = await showModalBottomSheet<int>(
          context: context,
          isScrollControlled: true,
          builder: (context) => _QuickAddCategorySheet(isExpense: isExpense),
        );
        // Made, so chosen: the entry the user started is what they came for.
        if (id != null && context.mounted) Navigator.of(context).pop(id);
      },
      child: Column(
        children: [
          const SizedBox(height: 4),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.primary, width: 2),
            ),
            child: Icon(Icons.add, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              'New',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium,
            ),
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
