/// Persistence mapping for [Account].
///
/// Follows the shape `transaction_model.dart` established, including its two
/// sharp edges: `created_at` is persistence bookkeeping and lives on the model
/// rather than the entity, and `Equatable` compares `runtimeType`, so a model
/// never equals an identical entity and [AccountModel.toEntity] exists to
/// convert at the repository boundary.
library;

import '../../domain/entities/account.dart';

/// An [Account] that can be written to and read from SQLite.
class AccountModel extends Account {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const AccountModel({
    required super.name,
    required super.icon,
    required super.initialBalanceDate,
    super.id,
    super.type,
    super.currency,
    super.initialBalanceCents,
    super.currentBalanceCents,
    super.includeInTotal,
    super.isArchived,
    this.userId = 1,
    this.createdAt,
  });

  /// Wraps an entity so it can be written.
  factory AccountModel.fromEntity(
    Account account, {
    int userId = 1,
    DateTime? createdAt,
  }) => AccountModel(
    id: account.id,
    name: account.name,
    icon: account.icon,
    type: account.type,
    currency: account.currency,
    initialBalanceCents: account.initialBalanceCents,
    currentBalanceCents: account.currentBalanceCents,
    initialBalanceDate: account.initialBalanceDate,
    includeInTotal: account.includeInTotal,
    isArchived: account.isArchived,
    userId: userId,
    createdAt: createdAt,
  );

  /// Rebuilds a model from an `accounts` row.
  factory AccountModel.fromMap(Map<String, Object?> map) => AccountModel(
    id: map['id'] as int?,
    name: map['name']! as String,
    icon: map['icon']! as String,
    type: _decodeType(map['type']! as String),
    currency: map['currency']! as String,
    initialBalanceCents: map['initial_balance_cents']! as int,
    currentBalanceCents: map['current_balance_cents']! as int,
    initialBalanceDate: _decodeDate(map['initial_balance_date']! as String),
    includeInTotal: map['include_in_total'] == 1,
    isArchived: map['is_archived'] == 1,
    userId: map['user_id']! as int,
    createdAt: map['created_at'] == null
        ? null
        : DateTime.parse(map['created_at']! as String),
  );

  /// The owning user. Single-user today; the column exists for FR-SET-009.
  final int userId;

  /// When the row was first written. Null before it has been.
  final DateTime? createdAt;

  /// The row to write to `accounts`.
  ///
  /// `current_balance_cents` is included so an insert can carry the opening
  /// balance across, but callers updating an account must not use this to
  /// change it — see [toUpdateMap], which leaves the cache alone.
  Map<String, Object?> toMap({DateTime? now}) {
    final stamp = now ?? DateTime.now();
    return <String, Object?>{
      if (id != null) 'id': id,
      'user_id': userId,
      'name': name.trim(),
      'icon': icon,
      'type': type.storageValue,
      'currency': currency,
      'initial_balance_cents': initialBalanceCents,
      'current_balance_cents': currentBalanceCents,
      'initial_balance_date': encodeDate(initialBalanceDate),
      'include_in_total': includeInTotal ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
      'created_at': (createdAt ?? stamp).toIso8601String(),
    };
  }

  /// The columns an edit may change.
  ///
  /// Deliberately omits `current_balance_cents` and `created_at`. The balance
  /// is a cache maintained by the writes that move it (E-18); letting an edit
  /// form set it directly would put the cache and the history into a
  /// disagreement nothing in the schema could detect.
  ///
  /// It also omits `initial_balance_cents`, which *can* be edited — but only
  /// through a path that recomputes the balance afterwards, since changing the
  /// opening figure changes every total derived from it.
  Map<String, Object?> toUpdateMap() => <String, Object?>{
    'name': name.trim(),
    'icon': icon,
    'type': type.storageValue,
    'currency': currency,
    'initial_balance_cents': initialBalanceCents,
    'initial_balance_date': encodeDate(initialBalanceDate),
    'include_in_total': includeInTotal ? 1 : 0,
    'is_archived': isArchived ? 1 : 0,
  };

  /// A plain entity, safe to hand to the domain layer.
  Account toEntity() => Account(
    id: id,
    name: name,
    icon: icon,
    type: type,
    currency: currency,
    initialBalanceCents: initialBalanceCents,
    currentBalanceCents: currentBalanceCents,
    initialBalanceDate: initialBalanceDate,
    includeInTotal: includeInTotal,
    isArchived: isArchived,
  );

  /// Formats a date as the `YYYY-MM-DD` the schema stores, in local time.
  ///
  /// Local for the same reason transactions are: a user's "today" is the date
  /// on the wall, not the date at Greenwich.
  static String encodeDate(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-$month-$day';
  }

  static DateTime _decodeDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) {
      throw FormatException('Not a YYYY-MM-DD date', value);
    }
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// Decodes the column's string, which is not the enum's `name`.
  ///
  /// `AccountType.creditCard.name` is `creditCard`; the CHECK accepts only
  /// `credit_card`. The same trap as `TransferDirection.incoming` (E-16).
  static AccountType _decodeType(String value) => AccountType.values.firstWhere(
    (t) => t.storageValue == value,
    orElse: () => throw FormatException('Unknown account type', value),
  );
}
