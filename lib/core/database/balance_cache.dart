/// The one write that moves an account's cached balance. E-18.
///
/// `accounts.current_balance_cents` is a cache, moved inside the database
/// transaction of every row that moves it and re-derived from history by
/// `RecomputeAccountBalance`. Two features write such rows: a transaction
/// (`LedgerWriter`) and, since E-47, a debt carried through an account,
/// whose money movement is a ledger row of its own. They share this, so a
/// balance moves by one arithmetic however the row arrived.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

/// Moves the cached balance on [accountId] by [deltaCents].
///
/// Always called from inside a transaction, never on its own (E-18). The
/// arithmetic is exact because the column is `INTEGER` cents (E-06);
/// repeated increment of a `REAL` would drift.
Future<void> moveCachedBalance(
  DatabaseExecutor txn,
  int accountId,
  int deltaCents,
) async {
  if (deltaCents == 0) return;
  await txn.rawUpdate(
    'UPDATE accounts SET current_balance_cents = current_balance_cents + ? '
    'WHERE id = ?',
    [deltaCents, accountId],
  );
}
