/// The only place SQL is written for the money_plan feature.
///
/// Throws [CacheException] on failure and returns models; the repository
/// above converts. See `docs/ARCHITECTURE.md` §3.
///
/// ## One active plan, held here
///
/// `money_plans.is_active` says "1 = currently active plan", singular, and
/// FR-PLN-013 tracks *the* active plan. Nothing in the schema enforces
/// that (a partial unique index would, and would be a v2 migration), so it
/// is held by the two writes that can set the flag: [insert] with
/// `activate` and [activate] both clear every other plan's flag **in the
/// same transaction** as they set this one's. The alternative — callers
/// deactivate first, then activate — is two transactions with a moment
/// between them in which no plan, or two, is active, and a rule every
/// caller has to remember. This way it is an invariant the data layer
/// keeps, and the tests below assert it.
///
/// ## The spend cache is recounted when a plan becomes active
///
/// `plan_allocations.spent_amount_cents` is kept incrementally by the
/// transactions datasource, inside each expense's own write, for the plan
/// that is active *at the time of the write* (FR-PLN-013, E-18). That is
/// exact for a plan across the writes made while it is active, and blind to
/// everything before: a plan saved on the 14th over a month that began on
/// the 1st has never seen the first two weeks, and a plan re-activated
/// after a spell inactive missed whatever was written meanwhile. So the two
/// writes that make a plan active — [insert] with `isActive` and
/// [activate] — end with [_recomputeSpentWithin] in the same transaction,
/// and the figure is right from the first moment anything can read it. An
/// inactive plan's figure is "as of the last time it was active" and is
/// not maintained; it is recounted the moment that changes.
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/database/database_change_bus.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/budget_alert_evaluation.dart';
import '../models/money_plan_model.dart';
import '../models/plan_allocation_model.dart';

/// Reads and writes plans in the local encrypted database.
abstract interface class MoneyPlanLocalDataSource {
  /// Inserts [plan] and its allocations as one transaction, returning the
  /// plan id. When [plan.isActive], deactivates every other plan first and
  /// recounts the new plan's spend from the expenses already in its period.
  Future<int> insert(MoneyPlanModel plan);

  /// Sets [id] active and every other plan inactive, in one transaction,
  /// and recounts its spend from history.
  Future<void> activate(int id);

  /// Reads one plan with its allocations, or null.
  Future<MoneyPlanModel?> getById(int id);

  /// Reads the active plan with its allocations, or null.
  Future<MoneyPlanModel?> getActive();

  /// Reads every plan with its allocations, newest first. FR-PLN-015.
  Future<List<MoneyPlanModel>> listAll();

  /// The plan whose period ended most recently before [isoDay]
  /// (`YYYY-MM-DD`), with its allocations, or null. FR-PLN-014's "next
  /// period" seen from the other side: the plan a new one follows.
  Future<MoneyPlanModel?> getLatestEndingBefore(String isoDay);

  /// Rewrites the allocation figures of [planId]'s rows from
  /// [allocations], matched by category, in one transaction. Every category
  /// given must already have a row.
  Future<void> updateAllocations(
    int planId,
    List<PlanAllocationModel> allocations,
  );

  /// Re-derives every `spent_amount_cents` of [planId] from history and
  /// writes it, in one transaction. FR-PLN-013, E-18.
  Future<void> recomputeSpent(int planId);

  /// Moves each row of [changes] from its `from` level to its `to` level,
  /// only where the row still holds `from`, in one transaction; returns the
  /// ids that moved. FR-SET-007, E-35.
  ///
  /// Signals nothing: no screen draws `alerted_level`, and a signal would
  /// re-read every plan watcher for it.
  Future<Set<int>> recordAlertLevels(List<AlertLevelChange> changes);

  /// Fires after every successful write — by this datasource or, when the
  /// bus is shared, by any other.
  Stream<void> get changes;

  /// Closes [changes] if this datasource owns it.
  Future<void> dispose();
}

/// sqflite implementation of [MoneyPlanLocalDataSource].
class MoneyPlanLocalDataSourceImpl implements MoneyPlanLocalDataSource {
  /// Creates a datasource over an already-open [db].
  ///
  /// Pass [changeBus] to share the app's one change signal, as
  /// `injection.dart` does: FR-PLN-013's spend against the active plan
  /// moves when a *transaction* is written, so a plan watcher has to hear
  /// the transactions datasource too. Omit it and this datasource gets a
  /// private bus, hearing only its own writes.
  MoneyPlanLocalDataSourceImpl(this._db, {DatabaseChangeBus? changeBus})
    : _changes = changeBus ?? DatabaseChangeBus(),
      _ownsChanges = changeBus == null;

  final Database _db;
  final DatabaseChangeBus _changes;
  final bool _ownsChanges;

  @override
  Stream<void> get changes => _changes.changes;

  @override
  Future<void> dispose() async {
    if (_ownsChanges) await _changes.close();
  }

  void _notify() => _changes.notify();

  /// Allocation rows with the category's name alongside, so a plan reads
  /// back displayable without a second query per row.
  static const String _allocationsOf = '''
SELECT a.id, a.category_id, c.name AS category_name,
       a.allocated_amount_cents, a.spent_amount_cents, a.carry_over_cents,
       a.confidence_level, a.expense_class, a.is_user_modified, a.notes,
       a.alerted_level
  FROM plan_allocations a
  JOIN categories c ON c.id = a.category_id
 WHERE a.plan_id = ?
 ORDER BY a.id ASC
''';

  @override
  Future<int> insert(MoneyPlanModel plan) async {
    final id = await _guard('save the plan', () async {
      return _db.transaction((txn) async {
        if (plan.isActive) await _deactivateAll(txn);
        final planId = await txn.insert(
          'money_plans',
          plan.toMap(now: DateTime.now()),
        );
        for (final a in plan.allocationModels) {
          await txn.insert('plan_allocations', a.toMap(planId));
        }
        if (plan.isActive) await _recomputeSpentWithin(txn, planId);
        return planId;
      });
    });

    _notify();
    return id;
  }

  @override
  Future<void> activate(int id) async {
    await _guard('activate plan $id', () async {
      await _db.transaction((txn) async {
        await _deactivateAll(txn);
        final changed = await txn.update(
          'money_plans',
          {'is_active': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        // Inside the transaction, so a missing id rolls the deactivation
        // back rather than leaving no plan active.
        if (changed == 0) throw CacheException('No plan with id $id.');
        await _recomputeSpentWithin(txn, id);
      });
    });

    _notify();
  }

  @override
  Future<MoneyPlanModel?> getById(int id) => _guard('read plan $id', () async {
    final rows = await _db.query(
      'money_plans',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _withAllocations(rows.single);
  });

  @override
  Future<MoneyPlanModel?> getActive() =>
      _guard('read the active plan', () async {
        // `LIMIT 1` is belt and braces: the writes above never leave two.
        final rows = await _db.query(
          'money_plans',
          where: 'is_active = 1',
          orderBy: 'id DESC',
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return _withAllocations(rows.single);
      });

  @override
  Future<List<MoneyPlanModel>> listAll() => _guard('read the plans', () async {
    final rows = await _db.query('money_plans', orderBy: 'id DESC');
    // One allocations query per plan. A user has a handful of plans, not
    // hundreds; the join-once shape `_readSplits` uses is for lists that
    // grow with the ledger.
    return [for (final row in rows) await _withAllocations(row)];
  });

  @override
  Future<MoneyPlanModel?> getLatestEndingBefore(String isoDay) =>
      _guard('read the plan before $isoDay', () async {
        // Latest end first; the id breaks a tie between two plans over the
        // same days in favour of the one saved last.
        final rows = await _db.query(
          'money_plans',
          where: 'end_date < ?',
          whereArgs: [isoDay],
          orderBy: 'end_date DESC, id DESC',
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return _withAllocations(rows.single);
      });

  @override
  Future<void> updateAllocations(
    int planId,
    List<PlanAllocationModel> allocations,
  ) async {
    await _guard('update the allocations of plan $planId', () async {
      await _db.transaction((txn) async {
        for (final a in allocations) {
          final changed = await txn.update(
            'plan_allocations',
            a.toAllocationUpdateMap(),
            where: 'plan_id = ? AND category_id = ?',
            whereArgs: [planId, a.categoryId],
          );
          // All or nothing: a category that is not in the plan rolls back
          // every row already rewritten, so the total is never half-held.
          if (changed == 0) {
            throw CacheException(
              'Plan $planId has no allocation for category ${a.categoryId}.',
            );
          }
        }
      });
    });

    _notify();
  }

  @override
  Future<void> recomputeSpent(int planId) async {
    await _guard('recount the spending of plan $planId', () async {
      await _db.transaction((txn) => _recomputeSpentWithin(txn, planId));
    });

    _notify();
  }

  @override
  Future<Set<int>> recordAlertLevels(List<AlertLevelChange> changes) => _guard(
    'store the budget alert levels',
    () {
      return _db.transaction((txn) async {
        final moved = <int>{};
        for (final change in changes) {
          // The `from` in the WHERE is the whole point: a change computed
          // from a read that another evaluation has since acted on finds
          // the row already moved, updates nothing, and so announces
          // nothing.
          final updated = await txn.update(
            'plan_allocations',
            {'alerted_level': PlanAllocationModel.encodeAlertLevel(change.to)},
            where: 'id = ? AND alerted_level = ?',
            whereArgs: [
              change.allocationId,
              PlanAllocationModel.encodeAlertLevel(change.from),
            ],
          );
          if (updated > 0) moved.add(change.allocationId);
        }
        return moved;
      });
    },
  );

  /// Derives every allocation's spend of [planId] from history and writes
  /// it. The recount E-18 asks for, in the shape of
  /// `AccountLocalDataSourceImpl._recomputeWithin`.
  ///
  /// The transactions datasource keeps `spent_amount_cents` incrementally,
  /// inside each expense's own write. This is the thing that checks it: the
  /// same rows the analytics datasource counts as spending — unsplit
  /// expenses plus the parts of split ones (E-04), never income or a
  /// transfer (E-02) — summed per category over the plan's period,
  /// inclusive at both ends, and stored. A category with no spend gets 0
  /// (`SUM` over nothing is `NULL`, hence the `COALESCE`); an allocation
  /// row is never added or removed.
  ///
  /// Runs inside [insert] and [activate] (see the library comment) and
  /// behind [recomputeSpent] for the repair E-18 asks for — never on
  /// launch: a recount is `O(expenses in the period)`, and NFR-PER-001 is
  /// why nothing scans history on the cold-start path.
  Future<void> _recomputeSpentWithin(DatabaseExecutor txn, int planId) async {
    final plans = await txn.query(
      'money_plans',
      columns: ['start_date', 'end_date'],
      where: 'id = ?',
      whereArgs: [planId],
      limit: 1,
    );
    if (plans.isEmpty) throw CacheException('No plan with id $planId.');
    final from = plans.single['start_date'];
    final to = plans.single['end_date'];

    await txn.rawUpdate(
      '''
UPDATE plan_allocations
   SET spent_amount_cents = COALESCE((
         SELECT SUM(part.amount_cents)
           FROM (
             SELECT t.category_id AS category_id, t.amount_cents AS amount_cents
               FROM transactions t
              WHERE t.type = 'expense' AND t.is_split = 0
                AND t.date >= ? AND t.date <= ?
             UNION ALL
             SELECT s.category_id AS category_id, s.amount_cents AS amount_cents
               FROM transaction_splits s
               JOIN transactions t ON t.id = s.transaction_id
              WHERE t.type = 'expense'
                AND t.date >= ? AND t.date <= ?
           ) AS part
          WHERE part.category_id = plan_allocations.category_id
       ), 0)
 WHERE plan_id = ?
''',
      [from, to, from, to, planId],
    );
  }

  Future<MoneyPlanModel> _withAllocations(Map<String, Object?> plan) async {
    final allocations = await _db.rawQuery(_allocationsOf, [plan['id']]);
    return MoneyPlanModel.fromMap(plan, allocations);
  }

  static Future<void> _deactivateAll(DatabaseExecutor txn) =>
      txn.update('money_plans', {'is_active': 0}, where: 'is_active = 1');

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
