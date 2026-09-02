import 'package:equatable/equatable.dart';

/// What kind of movement a transaction records.
enum TransactionType {
  /// Money out. FR-EXP-001.
  expense,

  /// Money in. FR-INC-001.
  income,

  /// Money between the user's own accounts. FR-TRF-001.
  ///
  /// Neither income nor expense, and **must be excluded from analytics** —
  /// counting it inflates both totals, which is the most common bug in
  /// personal-finance apps (E-02).
  transfer;

  /// True for the two types that represent real money in or out.
  bool get affectsTotals => this != TransactionType.transfer;
}

/// Which half of a transfer a row is.
///
/// Exists because `amountCents` is always positive and both halves carry
/// [TransactionType.transfer], so without this nothing on the row says which
/// way the money went (E-16).
enum TransferDirection {
  /// Left this account.
  out,

  /// Arrived in this account.
  incoming,
}

/// One part of an expense split across categories. FR-EXP-010, E-04.
class TransactionSplit extends Equatable {
  /// Creates a split part.
  const TransactionSplit({
    required this.categoryId,
    required this.amountCents,
    this.id,
    this.note,
  });

  /// Row id, null before it is saved.
  final int? id;

  /// The category this part belongs to.
  final int categoryId;

  /// This part's share, in minor units. Always positive.
  final int amountCents;

  /// Optional note for this part alone.
  final String? note;

  @override
  List<Object?> get props => [id, categoryId, amountCents, note];
}

/// A single financial movement.
///
/// Pure Dart: no Flutter, no sqflite, no JSON. That is what lets the Money
/// Plan engine be tested without a device, and it is enforced by
/// `scripts/check_architecture.sh` rather than by good intentions.
///
/// ## Money is an integer
///
/// [amountCents] is minor units and always **positive** — direction is carried
/// by [type] and [transferDirection], never by the sign. A negative amount is
/// rejected rather than interpreted, because "negative income" has no agreed
/// meaning and different parts of an app will guess differently.
///
/// ## Invariants
///
/// The database enforces these too (see `v1_initial.dart`), but they are
/// checked here as well, because a `CHECK` constraint failing produces a
/// SQLite error message and this produces one a user can act on:
///
/// * a transfer has no category, and everything else has one (E-17)
/// * a transfer states its direction, and nothing else does (E-16)
/// * splits, when present, sum exactly to [amountCents] (E-04)
class Transaction extends Equatable {
  /// Creates a transaction.
  const Transaction({
    required this.accountId,
    required this.amountCents,
    required this.type,
    required this.date,
    this.id,
    this.categoryId,
    this.transferDirection,
    this.time,
    this.note,
    this.splits = const [],
    this.receiptScanId,
    this.isRecurring = false,
  });

  /// Row id, null before it is saved.
  final int? id;

  /// The account this row belongs to.
  final int accountId;

  /// The category. Null for transfers, required otherwise (E-17).
  final int? categoryId;

  /// Amount in minor units. Always positive.
  final int amountCents;

  /// Expense, income, or transfer.
  final TransactionType type;

  /// Which half of a transfer this is. Null unless [type] is a transfer.
  final TransferDirection? transferDirection;

  /// ISO-8601 date, `YYYY-MM-DD`.
  final DateTime date;

  /// Time of day, `HH:MM`. Optional — FR-EXP-001 makes it optional.
  final String? time;

  /// Free text. FR-EXP-001.
  final String? note;

  /// Category split parts. Empty for the ordinary single-category case.
  final List<TransactionSplit> splits;

  /// The receipt scan that produced this, if any. FR-RCP-009.
  final int? receiptScanId;

  /// Whether a recurring rule generated this. FR-EXP-008.
  final bool isRecurring;

  /// True when this row is split across categories.
  bool get isSplit => splits.isNotEmpty;

  /// The sum of the split parts, or zero when there are none.
  int get splitTotalCents =>
      splits.fold(0, (sum, split) => sum + split.amountCents);

  /// The category holding the largest share of a split.
  ///
  /// Stored on the row itself so list views and the donut chart render without
  /// joining `transaction_splits` — see E-04 on why the parent keeps a
  /// category at all.
  int? get dominantCategoryId {
    if (splits.isEmpty) return categoryId;
    return splits
        .reduce((a, b) => a.amountCents >= b.amountCents ? a : b)
        .categoryId;
  }

  /// A copy with the given fields replaced.
  Transaction copyWith({
    int? id,
    int? accountId,
    int? categoryId,
    int? amountCents,
    TransactionType? type,
    TransferDirection? transferDirection,
    DateTime? date,
    String? time,
    String? note,
    List<TransactionSplit>? splits,
    int? receiptScanId,
    bool? isRecurring,
  }) => Transaction(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    categoryId: categoryId ?? this.categoryId,
    amountCents: amountCents ?? this.amountCents,
    type: type ?? this.type,
    transferDirection: transferDirection ?? this.transferDirection,
    date: date ?? this.date,
    time: time ?? this.time,
    note: note ?? this.note,
    splits: splits ?? this.splits,
    receiptScanId: receiptScanId ?? this.receiptScanId,
    isRecurring: isRecurring ?? this.isRecurring,
  );

  @override
  List<Object?> get props => [
    id,
    accountId,
    categoryId,
    amountCents,
    type,
    transferDirection,
    date,
    time,
    note,
    splits,
    receiptScanId,
    isRecurring,
  ];
}
