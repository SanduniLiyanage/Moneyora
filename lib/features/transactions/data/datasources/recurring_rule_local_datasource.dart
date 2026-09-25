/// The only place SQL is written for recurring rules. FR-EXP-008,
/// FR-INC-004.
///
/// Throws [CacheException] on failure and returns models, per
/// `docs/ARCHITECTURE.md` §3.
///
/// Every write here writes the ledger too, and goes through [LedgerWriter]
/// — the insert a typed entry takes — inside the same database transaction
/// as the rule it belongs to, so a rule's entries move balances (E-18) and
/// plan spend (FR-PLN-013) exactly as a typed entry does, and the rule's
/// next due date cannot move without them or they without it.
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/database/database_change_bus.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/date_utils.dart';
import '../../domain/entities/transaction.dart';
import '../models/recurring_rule_model.dart';
import '../models/transaction_model.dart';
import 'ledger_writer.dart';

/// A due rule as stored, with the template row it copies.
typedef RecurringSeriesRow = ({
  RecurringRuleModel rule,
  TransactionModel? template,
});

/// Reads and writes recurring rules in the local encrypted database.
abstract interface class RecurringRuleLocalDataSource {
  /// Writes [first] as the template and [rule] beside it, linked both ways,
  /// in one database transaction, and returns the rule's id.
  Future<int> create({
    required TransactionModel first,
    required RecurringRuleModel rule,
  });

  /// Every active rule due on or before [today], oldest due date first,
  /// each with its template and the template's split parts.
  Future<List<RecurringSeriesRow>> due(DateTime today);

  /// Every rule, active and stopped, each with its template.
  Future<List<RecurringSeriesRow>> all();

  /// Stops [ruleId] posting. Throws when there is no such rule.
  Future<void> pause(int ruleId);

  /// Starts [ruleId] posting again, next due on [nextDueDate]. Throws when
  /// there is no such rule, or it has no template to copy (E-36).
  Future<void> resume(int ruleId, DateTime nextDueDate);

  /// Unlinks [ruleId]'s entries, keeping them, and deletes the rule, in one
  /// database transaction (E-36). Throws when there is no such rule.
  Future<void> delete(int ruleId);

  /// Posts [entries] for [ruleId] and moves it on, compare-and-set on
  /// [expectedNextDueDate]. Throws, writing nothing, when the rule has
  /// moved on or stopped since it was read.
  Future<List<int>> post({
    required int ruleId,
    required DateTime expectedNextDueDate,
    required List<TransactionModel> entries,
    required DateTime nextDueDate,
    required bool ended,
    required DateTime postedAt,
  });

  /// Fires after every successful write.
  Stream<void> get changes;

  /// Closes [changes] if this datasource made it.
  Future<void> dispose();
}

/// sqflite implementation of [RecurringRuleLocalDataSource].
class RecurringRuleLocalDataSourceImpl implements RecurringRuleLocalDataSource {
  /// Creates a datasource over an already-open [db].
  ///
  /// Pass [changeBus] to share the signal every ledger watcher listens to —
  /// which `injection.dart` does, because a rule's entries move balances,
  /// plan spend and the transaction list, and each of those screens must
  /// hear it. Omit it and this datasource gets a private bus.
  RecurringRuleLocalDataSourceImpl(this._db, {DatabaseChangeBus? changeBus})
    : _changes = changeBus ?? DatabaseChangeBus(),
      _ownsChanges = changeBus == null;

  final Database _db;
  final DatabaseChangeBus _changes;
  final bool _ownsChanges;

  @override
  Stream<void> get changes => _changes.changes;

  @override
  Future<void> dispose() async {
    // Never close a bus handed in — see AccountLocalDataSourceImpl.dispose.
    if (_ownsChanges) await _changes.close();
  }

  @override
  Future<int> create({
    required TransactionModel first,
    required RecurringRuleModel rule,
  }) async {
    _refuseTransfers([first]);

    final ruleId = await _guard('save the repeating entry', () {
      return _db.transaction((txn) async {
        // The two rows reference each other, so the order is forced, as a
        // transfer's is (E-15): the template first, then the rule naming
        // it, then the template's link back to the rule. All three in this
        // one transaction.
        final templateId = await LedgerWriter.insert(
          txn,
          TransactionModel.fromEntity(first.copyWith(isRecurring: true)),
        );
        final id = await txn.insert(
          'recurring_rules',
          RecurringRuleModel.fromEntity(
            rule.copyWith(templateTransactionId: templateId),
          ).toMap()..remove('id'),
        );
        await txn.update(
          'transactions',
          {'recurring_rule_id': id},
          where: 'id = ?',
          whereArgs: [templateId],
        );
        return id;
      });
    });

    _changes.notify();
    return ruleId;
  }

  @override
  Future<List<RecurringSeriesRow>> due(DateTime today) {
    return _guard('read the repeating entries due', () async {
      // Served by idx_recurring_next_due: a range on its first column. On
      // most launches this returns nothing, and that must stay one query.
      final ruleRows = await _db.query(
        'recurring_rules',
        where: 'is_active = 1 AND next_due_date <= ?',
        whereArgs: [encodeIsoDay(today)],
        orderBy: 'next_due_date ASC, id ASC',
      );
      if (ruleRows.isEmpty) return const <RecurringSeriesRow>[];
      return _withTemplates(ruleRows);
    });
  }

  @override
  Future<List<RecurringSeriesRow>> all() {
    return _guard('read the repeating entries', () async {
      // Every rule, in id order; the list's own order is the use case's.
      final ruleRows = await _db.query('recurring_rules', orderBy: 'id ASC');
      return _withTemplates(ruleRows);
    });
  }

  @override
  Future<void> pause(int ruleId) async {
    await _guard('pause the repeat', () async {
      final changed = await _db.update(
        'recurring_rules',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [ruleId],
      );
      if (changed != 1) throw CacheException('No repeat with id $ruleId.');
    });
    _changes.notify();
  }

  @override
  Future<void> resume(int ruleId, DateTime nextDueDate) async {
    await _guard('resume the repeat', () async {
      // Refused in SQL as well as in the use case: a rule whose template
      // went (E-36) has nothing to copy, and resuming it would only have
      // the next catch-up report that.
      final changed = await _db.update(
        'recurring_rules',
        {'is_active': 1, 'next_due_date': encodeIsoDay(nextDueDate)},
        where: 'id = ? AND template_tx_id IS NOT NULL',
        whereArgs: [ruleId],
      );
      if (changed != 1) {
        throw CacheException('No repeat with id $ruleId to resume.');
      }
    });
    _changes.notify();
  }

  @override
  Future<void> delete(int ruleId) async {
    await _guard('delete the repeat', () {
      return _db.transaction((txn) async {
        // E-36: `transactions.recurring_rule_id` has no delete action, so
        // the rule cannot go while an entry names it. The entries are money
        // that moved and stay; unlinked, they keep `is_recurring` and still
        // read as generated. Both statements or neither.
        await txn.update(
          'transactions',
          {'recurring_rule_id': null},
          where: 'recurring_rule_id = ?',
          whereArgs: [ruleId],
        );
        final deleted = await txn.delete(
          'recurring_rules',
          where: 'id = ?',
          whereArgs: [ruleId],
        );
        if (deleted != 1) throw CacheException('No repeat with id $ruleId.');
      });
    });
    _changes.notify();
  }

  /// [ruleRows] as models, each with its template and the template's
  /// split parts, in the order given. Two queries however many rules.
  Future<List<RecurringSeriesRow>> _withTemplates(
    List<Map<String, Object?>> ruleRows,
  ) async {
    final rules = ruleRows.map(RecurringRuleModel.fromMap).toList();
    final templateIds = {
      for (final rule in rules)
        if (rule.templateTransactionId != null) rule.templateTransactionId,
    }.toList();

    final templatesById = <int, TransactionModel>{};
    if (templateIds.isNotEmpty) {
      final placeholders = List.filled(templateIds.length, '?').join(', ');
      final rows = await _db.query(
        'transactions',
        where: 'id IN ($placeholders)',
        whereArgs: templateIds,
      );
      for (final row in rows) {
        // The parts are read so a template edited into a split is seen as
        // one, and refused, rather than copied as its parent row.
        templatesById[row['id']! as int] = await LedgerWriter.withSplits(
          _db,
          row,
        );
      }
    }

    return [
      for (final rule in rules)
        (rule: rule, template: templatesById[rule.templateTransactionId]),
    ];
  }

  @override
  Future<List<int>> post({
    required int ruleId,
    required DateTime expectedNextDueDate,
    required List<TransactionModel> entries,
    required DateTime nextDueDate,
    required bool ended,
    required DateTime postedAt,
  }) async {
    _refuseTransfers(entries);

    final ids = await _guard('post the repeating entries', () {
      return _db.transaction((txn) async {
        // Compare-and-set, first: the rule moves only if it is still where
        // the entries were computed from, and still active. A catch-up that
        // lost the race — launch and resume landing together — finds it
        // moved, and throws here, so the transaction rolls back before any
        // entry is written. An entry is posted once or not at all.
        final moved = await txn.update(
          'recurring_rules',
          {
            'next_due_date': encodeIsoDay(nextDueDate),
            if (entries.isNotEmpty)
              'last_created_at': postedAt.toIso8601String(),
            if (ended) 'is_active': 0,
          },
          where: 'id = ? AND is_active = 1 AND next_due_date = ?',
          whereArgs: [ruleId, encodeIsoDay(expectedNextDueDate)],
        );
        if (moved != 1) {
          throw const CacheException(
            'This repeat moved on while it was being posted, so nothing was '
            'posted twice.',
          );
        }

        final ids = <int>[];
        for (final entry in entries) {
          ids.add(await LedgerWriter.insert(txn, entry));
        }
        return ids;
      });
    });

    _changes.notify();
    return ids;
  }

  /// A rule copies an expense or an income; a transfer is three rows a
  /// single insert cannot write (E-15). The use cases refuse one first;
  /// this is the last line, as `TransactionLocalDataSource.add`'s is.
  static void _refuseTransfers(List<TransactionModel> rows) {
    if (rows.any((t) => t.type == TransactionType.transfer)) {
      throw const CacheException('A transfer cannot repeat.');
    }
  }

  /// Runs [body], turning any database error into a [CacheException].
  ///
  /// [action] is phrased to complete "Could not …".
  Future<T> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return await body();
    } on CacheException {
      rethrow;
    } on DatabaseException catch (e) {
      throw CacheException('Could not $action.', cause: e);
    }
  }
}
