import '../../domain/entities/receipt_line_item.dart';
import '../../domain/entities/receipt_scan.dart';

/// Persistence mapping for [ReceiptScanItem]: one `receipt_items` row.
class ReceiptScanItemModel extends ReceiptScanItem {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const ReceiptScanItemModel({
    required super.item,
    required super.confidence,
    super.id,
    super.suggestedCategoryId,
    super.confirmedCategoryId,
  });

  /// Wraps an entity so it can be written.
  factory ReceiptScanItemModel.fromEntity(ReceiptScanItem item) =>
      ReceiptScanItemModel(
        id: item.id,
        item: item.item,
        suggestedCategoryId: item.suggestedCategoryId,
        confirmedCategoryId: item.confirmedCategoryId,
        confidence: item.confidence,
      );

  /// Rebuilds a model from a `receipt_items` row.
  factory ReceiptScanItemModel.fromMap(Map<String, Object?> map) =>
      ReceiptScanItemModel(
        id: map['id'] as int?,
        item: ReceiptLineItem(
          name: map['name']! as String,
          quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
          unitPriceCents: map['unit_price_cents'] as int?,
          totalPriceCents: map['total_price_cents']! as int,
        ),
        suggestedCategoryId: map['suggested_category_id'] as int?,
        confirmedCategoryId: map['confirmed_category_id'] as int?,
        confidence: map['confidence_score'] as int? ?? 0,
      );

  /// The row, under [scanId].
  Map<String, Object?> toMap({required int scanId}) => {
    'receipt_scan_id': scanId,
    'name': item.name,
    'quantity': item.quantity,
    'unit_price_cents': item.unitPriceCents,
    'total_price_cents': item.totalPriceCents,
    'suggested_category_id': suggestedCategoryId,
    'confirmed_category_id': confirmedCategoryId,
    'confidence_score': confidence,
  };
}

/// Persistence mapping for [ReceiptScan]. FR-RCP-009, E-31.
///
/// `created_at` and `user_id` are bookkeeping and live here, not on the
/// entity, as `MoneyPlanModel` does it. `merchant_type` — a column v1 has
/// and the entity does not — is left null: the categoriser's merchant
/// context (FR-RCP-007's Layer 3) is a category, not a type, and no
/// requirement reads a type back.
class ReceiptScanModel extends ReceiptScan {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const ReceiptScanModel({
    required super.imagePath,
    required super.status,
    required List<ReceiptScanItemModel> super.items,
    super.id,
    super.merchantName,
    super.receiptDate,
    super.totalCents,
    super.taxCents,
    super.receiptNumber,
    super.confidence,
    this.userId = 1,
    this.createdAt,
  });

  /// Wraps an entity so it can be written.
  factory ReceiptScanModel.fromEntity(
    ReceiptScan scan, {
    int userId = 1,
    DateTime? createdAt,
  }) => ReceiptScanModel(
    id: scan.id,
    imagePath: scan.imagePath,
    status: scan.status,
    merchantName: scan.merchantName,
    receiptDate: scan.receiptDate,
    totalCents: scan.totalCents,
    taxCents: scan.taxCents,
    receiptNumber: scan.receiptNumber,
    confidence: scan.confidence,
    items: [for (final i in scan.items) ReceiptScanItemModel.fromEntity(i)],
    userId: userId,
    createdAt: createdAt,
  );

  /// Rebuilds a model from a `receipt_scans` row and its item rows.
  factory ReceiptScanModel.fromMap(
    Map<String, Object?> map,
    List<Map<String, Object?>> itemRows,
  ) => ReceiptScanModel(
    id: map['id'] as int?,
    imagePath: map['image_path']! as String,
    status: decodeStatus(map['status']! as String),
    merchantName: map['merchant_name'] as String?,
    receiptDate: switch (map['receipt_date']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
    totalCents: map['total_amount_cents'] as int?,
    taxCents: map['tax_amount_cents'] as int?,
    receiptNumber: map['receipt_number'] as String?,
    confidence: map['confidence_score'] as int? ?? 0,
    items: itemRows.map(ReceiptScanItemModel.fromMap).toList(),
    userId: map['user_id'] as int? ?? 1,
    createdAt: switch (map['created_at']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
  );

  /// Owner, always 1 until multi-user exists.
  final int userId;

  /// When the row was written.
  final DateTime? createdAt;

  /// The items, typed as models.
  List<ReceiptScanItemModel> get itemModels =>
      items.cast<ReceiptScanItemModel>();

  /// The `receipt_scans` row.
  Map<String, Object?> toMap({required DateTime now}) => {
    'user_id': userId,
    'image_path': imagePath,
    'merchant_name': merchantName,
    'receipt_date': receiptDate?.toIso8601String(),
    'total_amount_cents': totalCents,
    'tax_amount_cents': taxCents,
    'receipt_number': receiptNumber,
    'confidence_score': confidence,
    'status': encodeStatus(status),
    'created_at': (createdAt ?? now).toIso8601String(),
  };

  /// `status`'s stored form — the check constraint's spelling.
  static String encodeStatus(ReceiptScanStatus status) => switch (status) {
    ReceiptScanStatus.pending => 'pending',
    ReceiptScanStatus.confirmed => 'confirmed',
    ReceiptScanStatus.rejected => 'rejected',
  };

  /// The inverse of [encodeStatus]. Throws on a value the constraint
  /// would have refused.
  static ReceiptScanStatus decodeStatus(String stored) => switch (stored) {
    'pending' => ReceiptScanStatus.pending,
    'confirmed' => ReceiptScanStatus.confirmed,
    'rejected' => ReceiptScanStatus.rejected,
    _ => throw ArgumentError.value(stored, 'stored', 'Unknown scan status'),
  };
}
