import 'package:equatable/equatable.dart';

/// Where this phone stands on backups. FR-BAK-006.
class BackupStatus extends Equatable {
  /// Creates a status.
  const BackupStatus({
    required this.lastSavedAt,
    required this.firstSeenAt,
    required this.transactionCount,
  });

  /// When a backup was last saved from this phone, or null if never.
  final DateTime? lastSavedAt;

  /// When the app first checked, which "never backed up" counts from.
  final DateTime firstSeenAt;

  /// Transactions there are to lose. None, and a reminder has nothing to
  /// say.
  final int transactionCount;

  @override
  List<Object?> get props => [lastSavedAt, firstSeenAt, transactionCount];
}
