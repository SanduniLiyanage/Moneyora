import 'package:equatable/equatable.dart';

import 'category_suggestion.dart';
import 'receipt_line_item.dart';
import 'reviewed_receipt.dart';
import 'scanned_receipt.dart';

/// One line as it stands on the review screen: what was parsed, what was
/// suggested, and what the user has settled on so far. FR-RCP-008.
class ReviewDraftItem extends Equatable {
  /// Creates a line.
  const ReviewDraftItem({
    required this.key,
    required this.item,
    required this.suggestion,
    this.categoryId,
  });

  /// Identity for the screen's list, stable across edits to the line and
  /// fresh after a merge or a split, so a row's fields are rebuilt exactly
  /// when the line beneath them is a different one.
  final int key;

  /// The line, as parsed or as edited.
  final ReceiptLineItem item;

  /// What the categoriser said, kept so the record can say whether the
  /// user agreed (FR-RCP-015).
  final CategorySuggestion suggestion;

  /// The category the user has now — the suggestion until changed, and
  /// null while nothing was suggested and nothing chosen.
  final int? categoryId;

  /// True when the suggestion is worth a "Low Confidence" badge
  /// (FR-RCP-011): the only lead was the merchant's category, or nothing
  /// matched at all.
  bool get isLowConfidence =>
      suggestion.confidence < ReceiptReviewDraft.lowConfidenceBelow;

  ReviewDraftItem _with({ReceiptLineItem? item}) => ReviewDraftItem(
    key: key,
    item: item ?? this.item,
    suggestion: suggestion,
    categoryId: categoryId,
  );

  @override
  List<Object?> get props => [key, item, suggestion, categoryId];
}

/// The review screen's working copy of a scan. FR-RCP-008, FR-RCP-010,
/// FR-RCP-011.
///
/// Every edit the SRS lists — a field changed, a line discarded, two
/// merged, one split — is a method returning a new draft, so the screen
/// holds one value and a test can state each rule without a widget.
/// [toReviewed] is what Confirm hands `ConfirmReceipt`; it is null until
/// the draft is complete, and [unfinished] says why.
///
/// Decisions the SRS does not make:
/// - **The posting date starts as the receipt's.** A receipt found in a
///   coat pocket is dated when it was paid; when no date was read it is
///   today, and a misread date that lands in the future is left for the
///   user to see and change rather than silently replaced.
/// - **Merging joins two neighbours into one purchase.** The names are
///   joined with ` + ` unless they are the same, the totals are summed,
///   and quantity and unit price are dropped — the merged line is one
///   thing bought, not a count of anything. The upper line's suggestion
///   and category are kept; it was the line the user had in front of them.
/// - **Splitting keeps everything but the amount.** Both halves carry the
///   name, the suggestion and the category, and the user renames or
///   recategorises the one that differs. A split at zero or at the whole
///   amount is not a split.
/// - **Single-category mode is a view over the same draft.** Switching it
///   on hides the lines and posts one expense for the printed total (or
///   the lines' sum when no total was read) under one category; switching
///   it off brings every line back as it was, edits included. The one
///   line is named after the merchant and its suggestion is the
///   merchant's own category, so confirming it under something else
///   teaches the dictionary the merchant, not the word "receipt".
/// - **Low confidence is below 50.** `CategoriseReceipt` scores a seed
///   match at 65 or more and a merchant-only lead at 20, so the line
///   badges exactly the lines the dictionary had no word for.
class ReceiptReviewDraft extends Equatable {
  /// Creates a draft. Screens use [ReceiptReviewDraft.fromScanned].
  const ReceiptReviewDraft({
    required this.imagePath,
    required this.postedOn,
    required this.items,
    this.accountId,
    this.merchantName,
    this.receiptDate,
    this.totalCents,
    this.taxCents,
    this.receiptNumber,
    this.merchantCategoryId,
    this.merchantCategoryName,
    this.isSingleCategory = false,
    this.singleCategoryId,
    this.nextKey = 0,
  });

  /// The draft the screen opens with: every suggestion accepted, the
  /// posting date the receipt's or [today], no account yet.
  factory ReceiptReviewDraft.fromScanned(
    ScannedReceipt scanned, {
    required DateTime today,
  }) {
    final receipt = scanned.receipt;
    final parsed = receipt.receipt;
    final on = parsed.receiptDate ?? today;
    return ReceiptReviewDraft(
      imagePath: scanned.imagePath,
      postedOn: DateTime(on.year, on.month, on.day),
      items: [
        for (final (index, entry) in receipt.items.indexed)
          ReviewDraftItem(
            key: index,
            item: entry.item,
            suggestion: entry.suggestion,
            categoryId: entry.suggestion.categoryId,
          ),
      ],
      merchantName: parsed.merchantName,
      receiptDate: parsed.receiptDate,
      totalCents: parsed.totalCents,
      taxCents: parsed.taxCents,
      receiptNumber: parsed.receiptNumber,
      merchantCategoryId: receipt.merchantCategoryId,
      merchantCategoryName: receipt.merchantCategoryName,
      nextKey: receipt.items.length,
    );
  }

  /// A suggestion under this is badged "Low Confidence" (FR-RCP-011).
  static const int lowConfidenceBelow = 50;

  /// The photo the scan was read from.
  final String imagePath;

  /// The account the money left; null until chosen.
  final int? accountId;

  /// The day the expenses will be recorded on.
  final DateTime postedOn;

  /// The lines kept, in printed order.
  final List<ReviewDraftItem> items;

  /// The store, as printed or as corrected.
  final String? merchantName;

  /// The date and, when printed, the time on the receipt.
  final DateTime? receiptDate;

  /// The printed total, minor units.
  final int? totalCents;

  /// The printed tax or VAT figure, minor units.
  final int? taxCents;

  /// The receipt's own printed identifier (E-31).
  final String? receiptNumber;

  /// The category the dictionary gave the merchant, for the screen to say
  /// why a line was biased. Null when its name matched nothing.
  final String? merchantCategoryName;

  /// The category the dictionary gave the merchant, the suggestion for
  /// the single line in single-category mode. Null when its name matched
  /// nothing.
  final int? merchantCategoryId;

  /// FR-RCP-010: true when the whole receipt posts as one expense.
  final bool isSingleCategory;

  /// The category that one expense carries; null until chosen.
  final int? singleCategoryId;

  /// The next [ReviewDraftItem.key] to hand out.
  final int nextKey;

  /// What the kept lines add up to.
  int get itemsSumCents =>
      items.fold(0, (sum, i) => sum + i.item.totalPriceCents);

  /// True when the kept lines account for the printed total exactly; null
  /// when no total was read.
  bool? get itemsMatchTotal =>
      totalCents == null ? null : itemsSumCents == totalCents;

  /// The mean of the lines' confidences, rounded; 0 for none. The figure
  /// `ConfirmReceipt` stores on the scan, computed the same way.
  int get meanConfidence {
    if (items.isEmpty) return 0;
    final sum = items.fold(0, (s, i) => s + i.suggestion.confidence);
    return (sum / items.length).round();
  }

  /// True when the receipt as a whole earns the badge (FR-RCP-011).
  bool get isLowConfidence =>
      items.isNotEmpty && meanConfidence < lowConfidenceBelow;

  /// How many kept lines still have no category.
  int get uncategorisedCount => items.where((i) => i.categoryId == null).length;

  /// What single-category mode posts: the printed total, or the lines'
  /// sum when none was read.
  int get singleAmountCents => totalCents ?? itemsSumCents;

  /// The one line single-category mode posts, categorised as the draft
  /// stands. Named after the merchant, with the merchant's category as
  /// its suggestion.
  ReviewedItem _singleLine(int categoryId) => ReviewedItem(
    item: ReceiptLineItem(
      name: merchantName ?? 'Receipt total',
      totalPriceCents: singleAmountCents,
    ),
    categoryId: categoryId,
    suggestedCategoryId: merchantCategoryId,
  );

  /// Why [toReviewed] returns null, or null when it does not.
  ///
  /// Only the two gaps the draft itself can have; everything else that
  /// stops a confirm — a blank name, a zero amount, a future date — is
  /// `ConfirmReceipt.validate`'s to say, on the receipt this builds.
  String? get unfinished {
    if (accountId == null) return 'Choose an account.';
    if (isSingleCategory) {
      if (singleCategoryId == null) return 'Choose a category for the receipt.';
      return null;
    }
    if (uncategorisedCount > 0) return 'Choose a category for every item.';
    return null;
  }

  /// The receipt to confirm, or null while [unfinished] says why not.
  ReviewedReceipt? toReviewed() {
    final account = accountId;
    if (account == null || unfinished != null) return null;
    return ReviewedReceipt(
      imagePath: imagePath,
      accountId: account,
      postedOn: postedOn,
      items: isSingleCategory
          ? [_singleLine(singleCategoryId!)]
          : [
              for (final i in items)
                ReviewedItem(
                  item: i.item,
                  categoryId: i.categoryId!,
                  suggestedCategoryId: i.suggestion.categoryId,
                  confidence: i.suggestion.confidence,
                ),
            ],
      merchantName: merchantName,
      receiptDate: receiptDate,
      totalCents: totalCents,
      taxCents: taxCents,
      receiptNumber: receiptNumber,
    );
  }

  /// The merchant, corrected. Blank is no merchant.
  ReceiptReviewDraft withMerchant(String? name) {
    final trimmed = name?.trim();
    return _with(
      merchantName: () => trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
  }

  /// The account the money left.
  ReceiptReviewDraft withAccount(int accountId) =>
      _with(accountId: () => accountId);

  /// Single-category mode on or off. FR-RCP-010. The lines are kept either
  /// way; switching off shows them again as they were.
  ReceiptReviewDraft withSingleCategory({required bool on}) =>
      _with(isSingleCategory: on);

  /// The category the whole receipt posts under.
  ReceiptReviewDraft withSingleCategoryId(int categoryId) =>
      _with(singleCategoryId: () => categoryId);

  /// The day to record the expenses on; the time is dropped.
  ReceiptReviewDraft withPostedOn(DateTime day) =>
      _with(postedOn: DateTime(day.year, day.month, day.day));

  /// The line [key], renamed.
  ReceiptReviewDraft rename(int key, String name) => _update(
    key,
    (i) => i._with(
      item: ReceiptLineItem(
        name: name,
        totalPriceCents: i.item.totalPriceCents,
        quantity: i.item.quantity,
        unitPriceCents: i.item.unitPriceCents,
      ),
    ),
  );

  /// The line [key], with a new total. The unit price no longer holds, so
  /// it is dropped.
  ReceiptReviewDraft reprice(int key, int totalPriceCents) => _update(
    key,
    (i) => i._with(
      item: ReceiptLineItem(
        name: i.item.name,
        totalPriceCents: totalPriceCents,
        quantity: i.item.quantity,
      ),
    ),
  );

  /// The line [key], under [categoryId].
  ReceiptReviewDraft recategorise(int key, int categoryId) => _update(
    key,
    (i) => ReviewDraftItem(
      key: i.key,
      item: i.item,
      suggestion: i.suggestion,
      categoryId: categoryId,
    ),
  );

  /// With every category not in [ids] unset, so a line whose category was
  /// deleted since the scan asks again rather than posting a row the
  /// foreign key would refuse. The suggestion is kept as it was made.
  ReceiptReviewDraft keepingCategories(Iterable<int> ids) {
    final known = ids.toSet();
    final singleKnown =
        singleCategoryId == null || known.contains(singleCategoryId);
    if (singleKnown &&
        items.every(
          (i) => i.categoryId == null || known.contains(i.categoryId),
        )) {
      return this;
    }
    return _with(
      items: [
        for (final i in items)
          if (i.categoryId == null || known.contains(i.categoryId))
            i
          else
            ReviewDraftItem(key: i.key, item: i.item, suggestion: i.suggestion),
      ],
      singleCategoryId: singleKnown ? null : () => null,
    );
  }

  /// Without the line [key].
  ReceiptReviewDraft discard(int key) => _with(
    items: [
      for (final i in items)
        if (i.key != key) i,
    ],
  );

  /// True when [key] has a line below it to merge with.
  bool canMergeWithNext(int key) {
    final index = _indexOf(key);
    return index >= 0 && index < items.length - 1;
  }

  /// The line [key] and the one below it, as one line under a new key.
  ReceiptReviewDraft mergeWithNext(int key) {
    assert(canMergeWithNext(key), 'nothing below $key to merge with');
    final index = _indexOf(key);
    final upper = items[index];
    final lower = items[index + 1];
    final merged = ReviewDraftItem(
      key: nextKey,
      item: ReceiptLineItem(
        name: upper.item.name == lower.item.name
            ? upper.item.name
            : '${upper.item.name} + ${lower.item.name}',
        totalPriceCents:
            upper.item.totalPriceCents + lower.item.totalPriceCents,
      ),
      suggestion: upper.suggestion,
      categoryId: upper.categoryId ?? lower.categoryId,
    );
    return _with(
      items: [...items.take(index), merged, ...items.skip(index + 2)],
      nextKey: nextKey + 1,
    );
  }

  /// True when [firstCents] cuts [item] into two non-empty parts.
  static bool canSplit(ReceiptLineItem item, int firstCents) =>
      firstCents > 0 && firstCents < item.totalPriceCents;

  /// The line [key] as two lines: [firstCents], then the rest. Both carry
  /// the original's name, suggestion and category, under new keys.
  ReceiptReviewDraft split(int key, int firstCents) {
    final index = _indexOf(key);
    assert(index >= 0, 'no line $key');
    final line = items[index];
    assert(canSplit(line.item, firstCents), '$firstCents does not split');
    ReviewDraftItem part(int key, int cents) => ReviewDraftItem(
      key: key,
      item: ReceiptLineItem(name: line.item.name, totalPriceCents: cents),
      suggestion: line.suggestion,
      categoryId: line.categoryId,
    );
    return _with(
      items: [
        ...items.take(index),
        part(nextKey, firstCents),
        part(nextKey + 1, line.item.totalPriceCents - firstCents),
        ...items.skip(index + 1),
      ],
      nextKey: nextKey + 2,
    );
  }

  int _indexOf(int key) => items.indexWhere((i) => i.key == key);

  ReceiptReviewDraft _update(
    int key,
    ReviewDraftItem Function(ReviewDraftItem) change,
  ) => _with(items: [for (final i in items) i.key == key ? change(i) : i]);

  ReceiptReviewDraft _with({
    int? Function()? accountId,
    DateTime? postedOn,
    List<ReviewDraftItem>? items,
    String? Function()? merchantName,
    bool? isSingleCategory,
    int? Function()? singleCategoryId,
    int? nextKey,
  }) => ReceiptReviewDraft(
    imagePath: imagePath,
    postedOn: postedOn ?? this.postedOn,
    items: items ?? this.items,
    accountId: accountId == null ? this.accountId : accountId(),
    merchantName: merchantName == null ? this.merchantName : merchantName(),
    receiptDate: receiptDate,
    totalCents: totalCents,
    taxCents: taxCents,
    receiptNumber: receiptNumber,
    merchantCategoryId: merchantCategoryId,
    merchantCategoryName: merchantCategoryName,
    isSingleCategory: isSingleCategory ?? this.isSingleCategory,
    singleCategoryId: singleCategoryId == null
        ? this.singleCategoryId
        : singleCategoryId(),
    nextKey: nextKey ?? this.nextKey,
  );

  @override
  List<Object?> get props => [
    imagePath,
    accountId,
    postedOn,
    items,
    merchantName,
    receiptDate,
    totalCents,
    taxCents,
    receiptNumber,
    merchantCategoryId,
    merchantCategoryName,
    isSingleCategory,
    singleCategoryId,
    nextKey,
  ];
}
