/// When this phone last saved a backup. FR-BAK-006.
///
/// Throws [AppException] on failure, per the layer contract in
/// `docs/ARCHITECTURE.md` §3; `BackupRepositoryImpl` converts.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/errors/exceptions.dart';

/// Two dates about this phone, not about the ledger.
///
/// In the keychain rather than the `users` row because a restore replaces
/// every row with another phone's (E-38), and "when did *this* phone last
/// save a backup" is not something a backup should carry: restored, it
/// would say the new phone was backed up on a day it did not exist.
abstract class BackupLog {
  /// When a backup was last saved, or null if one never was.
  Future<DateTime?> lastSavedAt();

  /// Records that a backup was saved at [at].
  Future<void> recordSaved(DateTime at);

  /// When this log first answered, recording [now] the first time it is
  /// asked — the date "no backup yet" is counted from.
  Future<DateTime> firstSeenAt(DateTime now);
}

/// Fulfils [BackupLog] over the platform keychain.
class SecureStorageBackupLog implements BackupLog {
  /// Creates a log over [storage], defaulting to the platform's.
  SecureStorageBackupLog({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Keychain entry holding the last save. Permanent: renaming it forgets
  /// every phone's last backup.
  static const String lastSavedKey = 'backup.lastSavedAt';

  /// Keychain entry holding the first time the log was read.
  static const String firstSeenKey = 'backup.firstSeenAt';

  @override
  Future<DateTime?> lastSavedAt() => _attempt(() async {
    final stored = await _storage.read(key: lastSavedKey);
    return stored == null ? null : DateTime.tryParse(stored);
  });

  @override
  Future<void> recordSaved(DateTime at) => _attempt(
    () =>
        _storage.write(key: lastSavedKey, value: at.toUtc().toIso8601String()),
  );

  @override
  Future<DateTime> firstSeenAt(DateTime now) => _attempt(() async {
    final stored = await _storage.read(key: firstSeenKey);
    if (stored != null) {
      if (DateTime.tryParse(stored) case final seen?) return seen;
    }
    await _storage.write(
      key: firstSeenKey,
      value: now.toUtc().toIso8601String(),
    );
    return now;
  });

  static Future<T> _attempt<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Exception catch (e) {
      throw CacheException('Could not read when you last backed up.', cause: e);
    }
  }
}
