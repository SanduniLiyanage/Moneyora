import 'package:sqflite_sqlcipher/sqflite.dart';

import 'database_helper.dart';

/// A count of what the database currently holds.
///
/// Sprint 1's visible proof that the stack works on a device: the encrypted
/// file opened, the migration ran, and the seed landed. Replaced by the real
/// home screen in Sprint 4.
class DatabaseSummary {
  /// Creates a summary.
  const DatabaseSummary({
    required this.schemaVersion,
    required this.accounts,
    required this.categories,
    required this.transactions,
  });

  /// Highest migration applied.
  final int schemaVersion;

  /// Rows in `accounts`.
  final int accounts;

  /// Rows in `categories`.
  final int categories;

  /// Rows in `transactions`.
  final int transactions;
}

/// Reads a [DatabaseSummary] from [db].
///
/// This lives in `core/database/` rather than beside the provider that calls
/// it because it contains SQL, and `scripts/check_architecture.sh` allows SQL
/// in exactly two places. The rule caught this on its first outing: the query
/// was originally written inline in `injection.dart`, which would have made
/// dependency wiring a place where SQL is normal.
Future<DatabaseSummary> readDatabaseSummary(Database db) async {
  Future<int> count(String table) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
      0;

  final versions = await DatabaseHelper.appliedVersions(db);
  return DatabaseSummary(
    schemaVersion: versions.isEmpty
        ? 0
        : versions.reduce((a, b) => a > b ? a : b),
    accounts: await count('accounts'),
    categories: await count('categories'),
    transactions: await count('transactions'),
  );
}

/// Whether the database has never been seeded.
///
/// Also here rather than in the provider, for the same reason.
Future<bool> isFirstLaunch(Database db) async {
  final existing = await db.query('users', limit: 1);
  return existing.isEmpty;
}
