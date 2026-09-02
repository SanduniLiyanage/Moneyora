/// Persistence mapping for [Transaction] and its split parts.
///
/// The entity is pure Dart and knows nothing about SQLite; this file is the
/// single place that knows the column names, the `TEXT` encodings and the
/// two-tables-one-concept shape of a split. Everything SQL-flavoured about a
/// transaction lives here or in the datasource, and nowhere else.
///
/// ## What the model owns, and what it does not
///
/// `created_at` and `updated_at` are persistence bookkeeping: nothing in the
/// domain asks when a row was written, so they are fields of the **model**.
/// `recurring_rule_id` and `receipt_scan_id` look similar and are not — they
/// are real relationships (FR-EXP-008, FR-RCP-009), so they live on the
/// entity. The test of which is which: would the rule still make sense if the
/// app stored its data in a text file? A recurring rule would. A row's write
/// timestamp would not.
///
/// ## Equality has a sharp edge
///
/// `Equatable` compares `runtimeType`, so a [TransactionModel] is **never**
/// equal to a plain [Transaction] even when every field matches. That is why
/// [TransactionModel.toEntity] exists and why the repository calls it before
/// returning: a test that expects an entity and receives a model gets a
/// failure whose message shows two identical-looking objects, which is a
/// genuinely miserable afternoon. Convert at the boundary and it cannot
/// happen.
library;

import '../../domain/entities/transaction.dart';

/// A [Transaction] that can be written to and read from SQLite.
class TransactionModel extends Transaction {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const TransactionModel({
    required super.accountId,
    required super.amountCents,
    required super.type,
    required super.date,
    super.id,
    super.categoryId,
    super.transferDirection,
    super.time,
    super.note,
    super.splits,
    super.receiptScanId,
    super.receiptImagePath,
    super.recurringRuleId,
    super.isRecurring,
    this.createdAt,
    this.updatedAt,
  });

  /// Wraps an entity so it can be written.
  ///
  /// [createdAt] is null for a row that has never been saved; [toMap] stamps
  /// it on the first write and preserves it on every write after.
  factory TransactionModel.fromEntity(
    Transaction transaction, {
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TransactionModel(
    id: transaction.id,
    accountId: transaction.accountId,
    categoryId: transaction.categoryId,
    amountCents: transaction.amountCents,
    type: transaction.type,
    transferDirection: transaction.transferDirection,
    date: transaction.date,
    time: transaction.time,
    note: transaction.note,
    splits: transaction.splits,
    receiptScanId: transaction.receiptScanId,
    receiptImagePath: transaction.receiptImagePath,
    recurringRuleId: transaction.recurringRuleId,
    isRecurring: transaction.isRecurring,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// Rebuilds a model from a `transactions` row.
  ///
  /// [splitRows] are the matching `transaction_splits` rows. They are optional
  /// because most reads do not need them: the parent row carries the dominant
  /// category and `is_split` (E-04), so a list view renders without the join.
  /// Passing none for a row whose `is_split` is 1 yields a **header** — a
  /// faithful read of what was asked for, not an error.
  factory TransactionModel.fromMap(
    Map<String, Object?> map, {
    List<Map<String, Object?>> splitRows = const [],
  }) => TransactionModel(
    id: map['id'] as int?,
    accountId: map['account_id']! as int,
    categoryId: map['category_id'] as int?,
    amountCents: map['amount_cents']! as int,
    type: _decodeType(map['type']! as String),
    transferDirection: _decodeDirection(map['transfer_direction'] as String?),
    date: _decodeDate(map['date']! as String),
    time: map['time'] as String?,
    note: map['note'] as String?,
    splits: splitRows.map(TransactionSplitMapper.fromMap).toList(),
    receiptScanId: map['receipt_scan_id'] as int?,
    receiptImagePath: map['receipt_image_path'] as String?,
    recurringRuleId: map['recurring_rule_id'] as int?,
    isRecurring: _decodeBool(map['is_recurring']),
    createdAt: _decodeTimestamp(map['created_at'] as String?),
    updatedAt: _decodeTimestamp(map['updated_at'] as String?),
  );

  /// When the row was first written. Null before it has been.
  ///
  /// Deliberately absent from `props`: the model adds persistence bookkeeping,
  /// not identity, so two models of the same transaction stay equal whatever
  /// their timestamps say.
  final DateTime? createdAt;

  /// When the row was last written. Recomputed by [toMap] on every write.
  final DateTime? updatedAt;

  /// The row to write to `transactions`.
  ///
  /// `id` is omitted when null so SQLite assigns one.
  ///
  /// [now] exists so tests can pin the clock. Production callers omit it.
  Map<String, Object?> toMap({DateTime? now}) {
    // created_at is carried over; updated_at is *always* recomputed. The two
    // look symmetrical and are not, which is exactly why this is easy to get
    // wrong: an update that copies updated_at back out of fromMap leaves a row
    // claiming it has not changed since the day it was created.
    final stamp = now ?? DateTime.now();
    return <String, Object?>{
      if (id != null) 'id': id,
      'account_id': accountId,
      'category_id': categoryId,
      'amount_cents': amountCents,
      'type': _encodeType(type),
      'transfer_direction': _encodeDirection(transferDirection),
      'date': encodeDate(date),
      'time': time,
      'note': note,
      'receipt_image_path': receiptImagePath,
      'is_recurring': isRecurring ? 1 : 0,
      'recurring_rule_id': recurringRuleId,
      'receipt_scan_id': receiptScanId,
      // Derived, never taken from a caller. The column is a denormalised copy
      // of "are there child rows", and the only way it can drift out of step
      // with `transaction_splits` is if something sets it independently.
      'is_split': splits.isNotEmpty ? 1 : 0,
      'created_at': (createdAt ?? stamp).toIso8601String(),
      'updated_at': stamp.toIso8601String(),
    };
  }

  /// The rows to write to `transaction_splits`, empty when unsplit.
  ///
  /// [transactionId] is passed in rather than read from [id] because on an
  /// insert the parent's id does not exist until the parent row is written —
  /// the datasource inserts the parent, reads the id back, then calls this,
  /// all inside one `BEGIN … COMMIT` (E-04).
  List<Map<String, Object?>> splitMaps(int transactionId) => splits
      .map((s) => TransactionSplitMapper.toMap(s, transactionId: transactionId))
      .toList();

  /// A plain entity, safe to hand to the domain layer.
  ///
  /// Not cosmetic — see the library comment. A model returned where an entity
  /// is expected compares unequal to an identical entity.
  Transaction toEntity() => Transaction(
    id: id,
    accountId: accountId,
    categoryId: categoryId,
    amountCents: amountCents,
    type: type,
    transferDirection: transferDirection,
    date: date,
    time: time,
    note: note,
    splits: splits,
    receiptScanId: receiptScanId,
    receiptImagePath: receiptImagePath,
    recurringRuleId: recurringRuleId,
    isRecurring: isRecurring,
  );

  /// Formats [date] as the `YYYY-MM-DD` the schema stores.
  ///
  /// **The local calendar date, deliberately.** Serialising through UTC would
  /// store tomorrow's date for anything entered after 18:30 in Colombo
  /// (UTC+5:30): an expense at 23:30 on the 2nd would land on the 3rd, and
  /// then the daily grouping of FR-EXP-006, every date-range filter and the
  /// Money Plan's month buckets would all inherit the shift. A user's "today"
  /// is the date on the wall, not the date at Greenwich.
  ///
  /// Any time component is dropped: the entity keeps the time separately in
  /// [Transaction.time], and `date` is a date.
  static String encodeDate(DateTime date) {
    final local = date.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static DateTime _decodeDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) {
      throw FormatException('Not a YYYY-MM-DD date', value);
    }
    // Local midnight, matching what encodeDate wrote.
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static DateTime? _decodeTimestamp(String? value) =>
      value == null ? null : DateTime.parse(value);

  // Written as explicit switches rather than `.name` / `byName`. For `type`
  // the two happen to agree; for `transferDirection` they do not —
  // `TransferDirection.incoming.name` is 'incoming', and the column's CHECK
  // accepts only 'in'. Deriving one encoding from `.name` and not the other
  // would leave the next reader guessing which enums are safe to rename.
  static String _encodeType(TransactionType type) => switch (type) {
    TransactionType.expense => 'expense',
    TransactionType.income => 'income',
    TransactionType.transfer => 'transfer',
  };

  static TransactionType _decodeType(String value) => switch (value) {
    'expense' => TransactionType.expense,
    'income' => TransactionType.income,
    'transfer' => TransactionType.transfer,
    _ => throw FormatException('Unknown transaction type', value),
  };

  static String? _encodeDirection(TransferDirection? direction) =>
      switch (direction) {
        null => null,
        TransferDirection.out => 'out',
        TransferDirection.incoming => 'in',
      };

  static TransferDirection? _decodeDirection(String? value) => switch (value) {
    null => null,
    'out' => TransferDirection.out,
    'in' => TransferDirection.incoming,
    _ => throw FormatException('Unknown transfer direction', value),
  };

  /// SQLite has no boolean type; the schema stores 0 and 1.
  static bool _decodeBool(Object? value) => value == 1;
}

/// Maps [TransactionSplit] to and from `transaction_splits` rows. E-04.
///
/// Static helpers rather than a `TransactionSplitModel extends
/// TransactionSplit`, so that a split read back from the database is the
/// *same type* as one built in the domain layer. A subclass would make
/// `fromMap(toMap(x)) == x` fail on the parent's `splits` list for the
/// `runtimeType` reason given above, and a split carries no persistence
/// metadata that would justify paying that price.
abstract final class TransactionSplitMapper {
  /// Rebuilds a split part from a `transaction_splits` row.
  static TransactionSplit fromMap(Map<String, Object?> map) => TransactionSplit(
    id: map['id'] as int?,
    categoryId: map['category_id']! as int,
    amountCents: map['amount_cents']! as int,
    note: map['note'] as String?,
  );

  /// The row to write. [transactionId] is the parent's id.
  static Map<String, Object?> toMap(
    TransactionSplit split, {
    required int transactionId,
  }) => <String, Object?>{
    if (split.id != null) 'id': split.id,
    'transaction_id': transactionId,
    'category_id': split.categoryId,
    'amount_cents': split.amountCents,
    'note': split.note,
  };
}
