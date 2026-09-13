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
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/database/database_change_bus.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/money_plan_model.dart';
import '../models/plan_allocation_model.dart';

/// Reads and writes plans in the local encrypted database.
abstract interface class MoneyPlanLocalDataSource {
  /// Inserts [plan] and its allocations as one transaction, returning the
  /// plan id. When [plan.isActive], deactivates every other plan first.
  Future<int> insert(MoneyPlanModel plan);

  /// Sets [id] active and every other plan inactive, in one transaction.
  Future<void> activate(int id);

  /// Reads one plan with its allocations, or null.
  Future<MoneyPlanModel?> getById(int id);

  /// Reads the active plan with its allocations, or null.
  Future<MoneyPlanModel?> getActive();

  /// Rewrites the allocation figures of [planId]'s rows from
  /// [allocations], matched by category, in one transaction. Every category
  /// given must already have a row.
  Future<void> updateAllocations(
    int planId,
    List<PlanAllocationModel> allocations,
  );

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
       a.allocated_amount_cents, a.spent_amount_cents, a.confidence_level,
       a.expense_class, a.is_user_modified, a.notes
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
