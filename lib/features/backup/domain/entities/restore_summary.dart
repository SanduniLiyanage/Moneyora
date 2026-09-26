import 'package:equatable/equatable.dart';

/// What a restore brought back, for the sentence the screen shows after it.
/// FR-BAK-005.
class RestoreSummary extends Equatable {
  /// Creates a summary.
  const RestoreSummary({
    required this.backedUpAt,
    required this.transactionCount,
    required this.photoCount,
  });

  /// When the backup was made, on the phone that made it.
  final DateTime backedUpAt;

  /// Transaction rows now in the ledger.
  final int transactionCount;

  /// Receipt photos restored and sealed under this phone's key.
  final int photoCount;

  @override
  List<Object?> get props => [backedUpAt, transactionCount, photoCount];
}
