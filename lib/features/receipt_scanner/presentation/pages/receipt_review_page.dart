import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/account_reader.dart';
import '../../../../core/ports/category_reader.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/category_suggestion.dart';
import '../../domain/entities/receipt_review_draft.dart';
import '../../domain/entities/scanned_receipt.dart';
import '../../domain/usecases/confirm_receipt.dart';
import '../providers/receipt_scanner_providers.dart';

/// Review & Confirm: the scan as read, corrected by hand, and posted.
/// FR-RCP-008, FR-RCP-009, FR-RCP-010, FR-RCP-011; the SDD's SCR-014.
///
/// Opens with a [ScannedReceipt] and holds one [ReceiptReviewDraft], which
/// every edit replaces — a line renamed, repriced or recategorised,
/// discarded, merged with the one below or split in two, the merchant
/// corrected, the account and the posting day chosen. Confirm hands
/// `ConfirmReceipt` what the draft builds, and is disabled for exactly the
/// reasons that use case would refuse it: the draft's own two gaps, then
/// `ConfirmReceipt.validate` on the receipt it would send. The reason is
/// printed above the button rather than discovered on tapping it.
///
/// FR-RCP-010's single-category mode is a switch above the lines: on, the
/// lines fold away and one picker names the category the whole total
/// posts under; off, every line is back as it was. The draft keeps both.
///
/// Categories and accounts arrive through the `core/ports` readers, live,
/// the same way the entry screen gets them (E-27). A suggestion the
/// dictionary had no word for — a line categorised only by the shop, or
/// not at all — carries FR-RCP-011's "Low confidence" badge, and the
/// receipt as a whole does when the mean is low.
///
/// Discard leaves without writing anything. A rejected scan record would
/// be the honest thing to keep for FR-RCP-013's history, but until
/// FR-RCP-012 stores the image the record would point at a photo the
/// picker's cache is free to delete.
class ReceiptReviewPage extends ConsumerStatefulWidget {
  /// Creates the screen for [scanned]. [now] is the clock, injectable for
  /// tests.
  const ReceiptReviewPage({required this.scanned, super.key, this.now});

  /// The photo and what was read off it.
  final ScannedReceipt scanned;

  /// The clock. `DateTime.now()` when null.
  final DateTime? now;

  @override
  ConsumerState<ReceiptReviewPage> createState() => _ReceiptReviewPageState();
}

class _ReceiptReviewPageState extends ConsumerState<ReceiptReviewPage> {
  late ReceiptReviewDraft _draft = ReceiptReviewDraft.fromScanned(
    widget.scanned,
    today: widget.now ?? DateTime.now(),
  );

  void _edit(ReceiptReviewDraft Function(ReceiptReviewDraft) change) =>
      setState(() => _draft = change(_draft));

  Future<void> _confirm() async {
    final reviewed = _draft.toReviewed();
    if (reviewed == null) return;

    final confirmation = await ref
        .read(confirmReceiptControllerProvider.notifier)
        .confirm(reviewed);
    if (!mounted) return;

    if (confirmation == null) {
      final error = ref.read(confirmReceiptControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is Failure ? error.message : 'Could not save the receipt.',
          ),
        ),
      );
      return;
    }

    final count = confirmation.transactionIds.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved $count expense${count == 1 ? '' : 's'}.')),
    );
    context.go(Routes.transactions);
  }

  Future<void> _split(ReviewDraftItem item) async {
    final firstCents = await showDialog<int>(
      context: context,
      builder: (_) => _SplitDialog(item: item),
    );
    if (firstCents == null) return;
    _edit((d) => d.split(item.key, firstCents));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(receiptCategoriesProvider);
    final accountsAsync = ref.watch(receiptAccountsProvider);
    final saving = ref.watch(confirmReceiptControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review receipt'),
        actions: [
          TextButton(
            onPressed: saving ? null : () => context.pop(),
            child: const Text('Discard'),
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _CatalogError(error: error),
        data: (categories) => accountsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _CatalogError(error: error),
          data: (accounts) {
            // Default to the account the receipt was paid from, or the
            // first one, rather than making the user choose on a fresh
            // install where there is only one — the entry screen's rule,
            // and the one place the draft is changed outside an edit.
            if (_draft.accountId == null) {
              if (_draft.defaultAccount(accounts) case final id?) {
                _draft = _draft.withAccount(id);
              }
            }
            _draft = _draft.keepingCategories([
              for (final c in categories) c.id,
            ]);

            final reviewed = _draft.toReviewed();
            final problem =
                _draft.unfinished ??
                (reviewed == null
                    ? null
                    : ConfirmReceipt.validate(reviewed)?.message);

            return SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _Header(
                          draft: _draft,
                          onMerchant: (name) =>
                              _edit((d) => d.withMerchant(name)),
                        ),
                        const SizedBox(height: 8),
                        Text('Paid from', style: theme.textTheme.titleSmall),
                        _AccountPicker(
                          accounts: accounts,
                          selectedId: _draft.accountId,
                          onSelected: (id) => _edit((d) => d.withAccount(id)),
                        ),
                        _DateField(
                          date: _draft.postedOn,
                          today: widget.now ?? DateTime.now(),
                          onChanged: (day) => _edit((d) => d.withPostedOn(day)),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'One category for the whole receipt',
                          ),
                          subtitle: Text(
                            _draft.isSingleCategory
                                ? '${formatCents(_draft.singleAmountCents)} '
                                      'as one expense.'
                                : 'Instead of one expense per line.',
                          ),
                          value: _draft.isSingleCategory,
                          onChanged: (on) =>
                              _edit((d) => d.withSingleCategory(on: on)),
                        ),
                        if (_draft.isSingleCategory)
                          _SingleCategoryPicker(
                            categories: categories,
                            selectedId: _draft.singleCategoryId,
                            merchantCategoryName: _draft.merchantCategoryName,
                            onSelected: (id) =>
                                _edit((d) => d.withSingleCategoryId(id)),
                          )
                        else ...[
                          Text(
                            'Items · ${_draft.items.length} · '
                            '${formatCents(_draft.itemsSumCents)}',
                            style: theme.textTheme.titleSmall,
                          ),
                          if (_draft.items.isEmpty)
                            // E-22: say what belongs here.
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'No items kept. Discard the receipt, or go '
                                'back and scan it again.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          for (final item in _draft.items)
                            _ItemCard(
                              key: ValueKey(item.key),
                              item: item,
                              categories: categories,
                              merchantCategoryName: _draft.merchantCategoryName,
                              canMerge: _draft.canMergeWithNext(item.key),
                              onRename: (name) =>
                                  _edit((d) => d.rename(item.key, name)),
                              onReprice: (cents) =>
                                  _edit((d) => d.reprice(item.key, cents)),
                              onCategory: (id) =>
                                  _edit((d) => d.recategorise(item.key, id)),
                              onDiscard: () =>
                                  _edit((d) => d.discard(item.key)),
                              onMerge: () =>
                                  _edit((d) => d.mergeWithNext(item.key)),
                              onSplit: () => _split(item),
                            ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (problem case final reason?)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              reason,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        FilledButton(
                          // Disabled rather than hidden, with the reason
                          // above it: a greyed button says "there is
                          // something still to do", and the line says what.
                          onPressed: problem == null && !saving
                              ? _confirm
                              : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          child: saving
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Confirm'),
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

/// The thumbnail, the merchant to correct, and what else was read.
class _Header extends StatelessWidget {
  const _Header({required this.draft, required this.onMerchant});

  final ReceiptReviewDraft draft;
  final ValueChanged<String> onMerchant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = draft.receiptDate;
    final time = ConfirmReceipt.timeOf(date);
    final details = <String>[
      if (date != null)
        'Dated ${date.year}-${_two(date.month)}-${_two(date.day)}'
            '${time == null ? '' : ' $time'}',
      if (draft.taxCents case final tax?) 'Tax ${formatCents(tax)}',
      if (draft.receiptNumber case final number?) 'No. $number',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(path: draft.imagePath),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: draft.merchantName ?? '',
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Merchant',
                      isDense: true,
                    ),
                    onChanged: onMerchant,
                  ),
                  const SizedBox(height: 8),
                  Text(switch (draft.totalCents) {
                    final total? => 'Total ${formatCents(total)}',
                    null => 'No total was read',
                  }, style: theme.textTheme.titleMedium),
                  if (details.isNotEmpty)
                    Text(details.join(' · '), style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    switch (draft.itemsMatchTotal) {
                      true => 'The items add up to the total.',
                      false =>
                        'The items add up to '
                            '${formatCents(draft.itemsSumCents)}, not the '
                            'total — check for a line missed or misread.',
                      null => 'Nothing to check the items against.',
                    },
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: draft.itemsMatchTotal == false
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ),
                  if (draft.isLowConfidence)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: _LowConfidenceBadge(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// The photo, when it is still on disk; a placeholder when not, rather
/// than an image error — the path is what matters and it is kept either
/// way.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 72,
        height: 96,
        child: file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

/// FR-RCP-011's badge.
class _LowConfidenceBadge extends StatelessWidget {
  const _LowConfidenceBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Low confidence',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

/// One line: its name and amount to edit, its category to keep or change,
/// the suggestion explained, and the three ways to reshape the list.
class _ItemCard extends StatefulWidget {
  const _ItemCard({
    required this.item,
    required this.categories,
    required this.merchantCategoryName,
    required this.canMerge,
    required this.onRename,
    required this.onReprice,
    required this.onCategory,
    required this.onDiscard,
    required this.onMerge,
    required this.onSplit,
    super.key,
  });

  final ReviewDraftItem item;
  final List<CategoryOption> categories;
  final String? merchantCategoryName;
  final bool canMerge;
  final ValueChanged<String> onRename;
  final ValueChanged<int> onReprice;
  final ValueChanged<int> onCategory;
  final VoidCallback onDiscard;
  final VoidCallback onMerge;
  final VoidCallback onSplit;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late final TextEditingController _name = TextEditingController(
    text: widget.item.item.name,
  );
  late final TextEditingController _amount = TextEditingController(
    text: formatCents(widget.item.item.totalPriceCents, showSymbol: false),
  );

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  String get _suggestionLabel {
    final s = widget.item.suggestion;
    final name = s.categoryName ?? 'Category ${s.categoryId}';
    return switch (s.source) {
      SuggestionSource.keyword => 'Suggested $name · ${s.confidence}%',
      SuggestionSource.userHistory =>
        'Suggested $name · ${s.confidence}% · you chose this before',
      SuggestionSource.merchant =>
        'Suggested $name · ${s.confidence}% · only because the shop is '
            '${widget.merchantCategoryName ?? name}',
      SuggestionSource.none => 'No suggestion',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = widget.item.item;
    final selected =
        widget.categories.any((c) => c.id == widget.item.categoryId)
        ? widget.item.categoryId
        : null;
    final quantity = line.quantity == line.quantity.roundToDouble()
        ? line.quantity.toInt().toString()
        : line.quantity.toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Item',
                      isDense: true,
                    ),
                    onChanged: widget.onRename,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.end,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'Rs ',
                      isDense: true,
                    ),
                    // Unreadable text is a zero, which Confirm refuses by
                    // name; a silently kept old figure would be saved.
                    onChanged: (text) =>
                        widget.onReprice(parseToCents(text) ?? 0),
                  ),
                ),
                PopupMenuButton<_ItemAction>(
                  tooltip: 'More',
                  onSelected: (action) => switch (action) {
                    _ItemAction.merge => widget.onMerge(),
                    _ItemAction.split => widget.onSplit(),
                    _ItemAction.discard => widget.onDiscard(),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _ItemAction.merge,
                      enabled: widget.canMerge,
                      child: const Text('Merge with next'),
                    ),
                    PopupMenuItem(
                      value: _ItemAction.split,
                      enabled: line.totalPriceCents > 1,
                      child: const Text('Split'),
                    ),
                    const PopupMenuItem(
                      value: _ItemAction.discard,
                      child: Text('Discard'),
                    ),
                  ],
                ),
              ],
            ),
            if (line.quantity != 1 || line.unitPriceCents != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(switch (line.unitPriceCents) {
                  final unit? => '$quantity × ${formatCents(unit)}',
                  null => 'Quantity $quantity',
                }, style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                isDense: true,
              ),
              hint: const Text('Choose a category'),
              items: [
                for (final c in widget.categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (id) {
                if (id != null) widget.onCategory(id);
              },
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_suggestionLabel, style: theme.textTheme.bodySmall),
                if (widget.item.isLowConfidence) const _LowConfidenceBadge(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _ItemAction { merge, split, discard }

/// The amount of the first part; the rest is the second. Returns the
/// cents, or null when dismissed.
class _SplitDialog extends StatefulWidget {
  const _SplitDialog({required this.item});

  final ReviewDraftItem item;

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  final TextEditingController _amount = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final cents = parseToCents(_amount.text);
    if (cents == null ||
        !ReceiptReviewDraft.canSplit(widget.item.item, cents)) {
      setState(
        () => _problem =
            'An amount between zero and '
            '${formatCents(widget.item.item.totalPriceCents)}.',
      );
      return;
    }
    Navigator.of(context).pop(cents);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Split ${widget.item.item.name}'),
    content: TextField(
      controller: _amount,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'First part',
        prefixText: 'Rs ',
        helperText:
            'The rest of ${formatCents(widget.item.item.totalPriceCents)} '
            'becomes a second line.',
        errorText: _problem,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Split')),
    ],
  );
}

/// FR-RCP-010: the one category the whole receipt posts under.
class _SingleCategoryPicker extends StatelessWidget {
  const _SingleCategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.merchantCategoryName,
    required this.onSelected,
  });

  final List<CategoryOption> categories;
  final int? selectedId;
  final String? merchantCategoryName;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = categories.any((c) => c.id == selectedId)
        ? selectedId
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<int>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Category for the receipt',
            ),
            hint: const Text('Choose a category'),
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (id) {
              if (id != null) onSelected(id);
            },
          ),
          if (merchantCategoryName case final name?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'The shop is $name.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// The account the money left, as chips — the entry screen's picker.
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No accounts yet.', style: theme.textTheme.bodyMedium),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

/// The posting day — the receipt's, or today's, until changed.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.today,
    required this.onChanged,
  });

  final DateTime date;
  final DateTime today;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(date, today);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.calendar_today_outlined),
      title: Text(
        isToday
            ? 'Record on today'
            : 'Record on ${date.year}-${date.month}-${date.day}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          // A misread date can land past today; the picker still opens,
          // on today, so the fix is one tap.
          initialDate: date.isAfter(today) ? today : date,
          firstDate: DateTime(2000),
          // No future dates: ConfirmReceipt rejects them anyway, and a
          // picker that offers what the validator refuses is a trap.
          lastDate: today,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        error is Failure
            ? (error as Failure).message
            : 'Could not load your categories and accounts.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
