@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/database/database_change_bus.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/features/transactions/data/datasources/recurring_rule_local_datasource.dart';
import 'package:moneyora/features/transactions/data/models/recurring_rule_model.dart';
import 'package:moneyora/features/transactions/data/models/transaction_model.dart';
import 'package:moneyora/features/transactions/data/repositories/recurring_rule_repository_impl.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/usecases/post_due_recurring_transactions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _OpenAccounts implements AccountReader {
  @override
  Stream<Either<Failure, List<AccountOption>>> watchAll() => Stream.value(
    const Right([
      AccountOption(id: 1, name: 'Cash', balanceCents: 0),
      AccountOption(id: 2, name: 'Bank', balanceCents: 0),
    ]),
  );
}

/// Against real SQLite, in memory: every claim here is about what the
/// database does — a rolled-back transaction, a foreign key, a
/// compare-and-set that matched no row.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late Database db;
  late DatabaseChangeBus bus;
  late RecurringRuleLocalDataSourceImpl source;

  const cash = 1;
  const bank = 2;
  const rent = 1;
  const salary = 2;
  const missingCategory = 999;

  setUp(() async {
    db = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          final batch = d.batch();
          for (final version in schemaMigrations.keys.toList()..sort()) {
            for (final statement in schemaMigrations[version]!) {
              batch.execute(statement);
            }
          }
          await batch.commit(noResult: true);
        },
        version: latestSchemaVersion,
      ),
    );

    const now = '2026-01-01T00:00:00Z';
    await db.insert('users', {'id': 1, 'created_at': now});
    for (final (id, name) in [(cash, 'Cash'), (bank, 'Bank')]) {
      await db.insert('accounts', {
        'id': id,
        'user_id': 1,
        'name': name,
        'icon': 'wallet',
        'initial_balance_date': '2026-01-01',
        'created_at': now,
      });
    }
    for (final (id, name, type) in [
      (rent, 'Rent', 'expense'),
      (salary, 'Salary', 'income'),
    ]) {
      await db.insert('categories', {
        'id': id,
        'user_id': 1,
        'name': name,
        'icon': 'dot',
        'color': '#3F51B5',
        'type': type,
      });
    }

    bus = DatabaseChangeBus();
    source = RecurringRuleLocalDataSourceImpl(db, changeBus: bus);
  });

  tearDown(() async {
    await source.dispose();
    await bus.close();
    await db.close();
  });

  // ── helpers ───────────────────────────────────────────────────────────────

  TransactionModel rentOn(
    DateTime date, {
    int categoryId = rent,
    int amountCents = 4500000,
    int accountId = cash,
  }) => TransactionModel(
    accountId: accountId,
    categoryId: categoryId,
    amountCents: amountCents,
    type: TransactionType.expense,
    date: date,
    time: '09:00',
    note: 'Rent',
  );

  RecurringRuleModel monthlyFrom(DateTime start) =>
      RecurringRuleModel.fromEntity(
        RecurringRule.startingOn(start, frequency: RecurrenceFrequency.monthly),
      );

  Future<int> balance(int accountId) async {
    final rows = await db.query(
      'accounts',
      columns: ['current_balance_cents'],
      where: 'id = ?',
      whereArgs: [accountId],
    );
    return rows.single['current_balance_cents']! as int;
  }

  Future<Map<String, Object?>> ruleRow(int id) async => (await db.query(
    'recurring_rules',
    where: 'id = ?',
    whereArgs: [id],
  )).single;

  Future<int> count(String table) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).single['n']!
          as int;

  Future<int> createMonthlyRent() => source.create(
    first: rentOn(DateTime(2026, 1, 5)),
    rule: monthlyFrom(DateTime(2026, 1, 5)),
  );

  // ── create ────────────────────────────────────────────────────────────────

  group('create', () {
    test('writes the template and the rule, linked both ways', () async {
      final ruleId = await createMonthlyRent();

      final rule = await ruleRow(ruleId);
      final templateId = rule['template_tx_id']! as int;
      expect(rule['frequency'], 'monthly');
      expect(rule['day_of_month'], 5);
      expect(rule['day_of_week'], isNull);
      expect(rule['start_date'], '2026-01-05');
      expect(rule['next_due_date'], '2026-02-05');
      expect(rule['last_created_at'], isNull);
      expect(rule['is_active'], 1);

      final template = (await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [templateId],
      )).single;
      expect(template['recurring_rule_id'], ruleId);
      expect(template['is_recurring'], 1);
      expect(template['date'], '2026-01-05');
      expect(template['amount_cents'], 4500000);
    });

    test(
      'the template moves the balance as a typed entry does (E-18)',
      () async {
        await createMonthlyRent();
        expect(await balance(cash), -4500000);
      },
    );

    test('stores a weekly rule on Sunday as 0, as users does', () async {
      // 2026-03-01 is a Sunday.
      final ruleId = await source.create(
        first: rentOn(DateTime(2026, 3)),
        rule: RecurringRuleModel.fromEntity(
          RecurringRule.startingOn(
            DateTime(2026, 3),
            frequency: RecurrenceFrequency.weekly,
          ),
        ),
      );
      expect((await ruleRow(ruleId))['day_of_week'], 0);
    });

    test('writes nothing when the template fails', () async {
      await expectLater(
        source.create(
          first: rentOn(DateTime(2026, 1, 5), categoryId: missingCategory),
          rule: monthlyFrom(DateTime(2026, 1, 5)),
        ),
        throwsA(isA<CacheException>()),
      );
      expect(await count('transactions'), 0);
      expect(await count('recurring_rules'), 0);
      expect(await balance(cash), 0);
    });

    test('refuses a transfer', () async {
      await expectLater(
        source.create(
          first: TransactionModel(
            accountId: cash,
            amountCents: 100,
            type: TransactionType.transfer,
            transferDirection: TransferDirection.out,
            date: DateTime(2026, 1, 5),
          ),
          rule: monthlyFrom(DateTime(2026, 1, 5)),
        ),
        throwsA(isA<CacheException>()),
      );
      expect(await count('transactions'), 0);
    });

    test('fires the change signal', () async {
      final fired = bus.changes.first;
      await createMonthlyRent();
      await expectLater(fired, completes);
    });
  });

  // ── due ───────────────────────────────────────────────────────────────────

  group('due', () {
    test('nothing is due on an empty table', () async {
      expect(await source.due(DateTime(2026, 6)), isEmpty);
    });

    test('returns active rules due on or before today, oldest first, with '
        'their templates', () async {
      final a = await createMonthlyRent(); // next 2026-02-05
      final b = await source.create(
        first: rentOn(DateTime(2026, 1, 2), accountId: bank),
        rule: monthlyFrom(DateTime(2026, 1, 2)), // next 2026-02-02
      );
      // Not yet due.
      await source.create(
        first: rentOn(DateTime(2026, 1, 20)),
        rule: monthlyFrom(DateTime(2026, 1, 20)), // next 2026-02-20
      );

      final due = await source.due(DateTime(2026, 2, 5));

      expect(due.map((d) => d.rule.id), [b, a]);
      expect(due.first.template!.accountId, bank);
      expect(due.first.template!.recurringRuleId, b);
      expect(due.last.rule.nextDueDate, DateTime(2026, 2, 5));
    });

    test('leaves out a stopped rule', () async {
      final id = await createMonthlyRent();
      await db.update(
        'recurring_rules',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(await source.due(DateTime(2026, 6)), isEmpty);
    });

    test('reads a template edited into a split with its parts', () async {
      final id = await createMonthlyRent();
      final templateId = (await ruleRow(id))['template_tx_id']! as int;
      await db.update(
        'transactions',
        {'is_split': 1},
        where: 'id = ?',
        whereArgs: [templateId],
      );
      await db.insert('transaction_splits', {
        'transaction_id': templateId,
        'category_id': rent,
        'amount_cents': 4500000,
      });

      final due = await source.due(DateTime(2026, 6));
      expect(due.single.template!.isSplit, isTrue);
    });

    test('a rule with no template comes back with none', () async {
      final id = await createMonthlyRent();
      await db.update(
        'recurring_rules',
        {'template_tx_id': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      final due = await source.due(DateTime(2026, 6));
      expect(due.single.template, isNull);
    });
  });

  // ── post ──────────────────────────────────────────────────────────────────

  group('post', () {
    Future<List<int>> postFeb(
      int ruleId, {
      DateTime? expected,
      List<TransactionModel>? entries,
      bool ended = false,
    }) => source.post(
      ruleId: ruleId,
      expectedNextDueDate: expected ?? DateTime(2026, 2, 5),
      entries:
          entries ??
          [
            rentOn(DateTime(2026, 2, 5)).copyWithRule(ruleId),
            rentOn(DateTime(2026, 3, 5)).copyWithRule(ruleId),
          ],
      nextDueDate: DateTime(2026, 4, 5),
      ended: ended,
      postedAt: DateTime(2026, 3, 20, 8, 15),
    );

    test('writes the entries and moves the rule, together', () async {
      final ruleId = await createMonthlyRent();

      final ids = await postFeb(ruleId);

      expect(ids, hasLength(2));
      final rows = await db.query(
        'transactions',
        where: 'recurring_rule_id = ? AND id <> ?',
        whereArgs: [ruleId, (await ruleRow(ruleId))['template_tx_id']],
        orderBy: 'date ASC',
      );
      expect(rows.map((r) => r['date']), ['2026-02-05', '2026-03-05']);
      expect(rows.map((r) => r['is_recurring']), [1, 1]);

      final rule = await ruleRow(ruleId);
      expect(rule['next_due_date'], '2026-04-05');
      expect(
        rule['last_created_at'],
        DateTime(2026, 3, 20, 8, 15).toIso8601String(),
      );
      expect(rule['is_active'], 1);
      // Template plus two entries.
      expect(await balance(cash), -3 * 4500000);
    });

    test(
      'an entry moves the active plan, as a typed one does (FR-PLN-013)',
      () async {
        final planId = await db.insert('money_plans', {
          'user_id': 1,
          'name': 'February',
          'period_type': 'month',
          'start_date': '2026-02-01',
          'end_date': '2026-02-28',
          'total_budget_cents': 5000000,
          'is_active': 1,
          'created_at': '2026-02-01T00:00:00Z',
        });
        await db.insert('plan_allocations', {
          'plan_id': planId,
          'category_id': rent,
          'allocated_amount_cents': 5000000,
          'confidence_level': 'high',
        });
        final ruleId = await createMonthlyRent();

        await postFeb(ruleId);

        final spent = await db.query(
          'plan_allocations',
          columns: ['spent_amount_cents'],
        );
        // February's entry only; March's falls outside the period.
        expect(spent.single['spent_amount_cents'], 4500000);
      },
    );

    test('a second post from the same due date writes nothing '
        '(compare-and-set)', () async {
      final ruleId = await createMonthlyRent();
      await postFeb(ruleId);
      final before = await count('transactions');

      await expectLater(postFeb(ruleId), throwsA(isA<CacheException>()));

      expect(await count('transactions'), before);
      expect((await ruleRow(ruleId))['next_due_date'], '2026-04-05');
      expect(await balance(cash), -3 * 4500000);
    });

    test('a rule stopped since it was read posts nothing', () async {
      final ruleId = await createMonthlyRent();
      await db.update(
        'recurring_rules',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [ruleId],
      );

      await expectLater(postFeb(ruleId), throwsA(isA<CacheException>()));
      expect(await count('transactions'), 1);
    });

    test('an entry that fails rolls the rule back too', () async {
      final ruleId = await createMonthlyRent();

      await expectLater(
        postFeb(
          ruleId,
          entries: [
            rentOn(DateTime(2026, 2, 5)).copyWithRule(ruleId),
            rentOn(
              DateTime(2026, 3, 5),
              categoryId: missingCategory,
            ).copyWithRule(ruleId),
          ],
        ),
        throwsA(isA<CacheException>()),
      );

      expect(await count('transactions'), 1);
      expect((await ruleRow(ruleId))['next_due_date'], '2026-02-05');
      expect(await balance(cash), -4500000);
    });

    test('ended stops the rule in the same write', () async {
      final ruleId = await createMonthlyRent();
      await postFeb(ruleId, ended: true);
      expect((await ruleRow(ruleId))['is_active'], 0);
    });

    test(
      'with no entries, moves the rule and leaves last_created_at',
      () async {
        final ruleId = await createMonthlyRent();
        final ids = await postFeb(ruleId, entries: const [], ended: true);
        expect(ids, isEmpty);
        final rule = await ruleRow(ruleId);
        expect(rule['last_created_at'], isNull);
        expect(rule['is_active'], 0);
      },
    );

    test('fires the change signal', () async {
      final ruleId = await createMonthlyRent();
      final fired = bus.changes.first;
      await postFeb(ruleId);
      await expectLater(fired, completes);
    });
  });

  // ── the rules list: all, pause, resume, delete ────────────────────────────

  group('all', () {
    test('returns every rule, active and stopped, with its template', () async {
      final a = await createMonthlyRent();
      final b = await source.create(
        first: rentOn(DateTime(2026, 1, 2), accountId: bank),
        rule: monthlyFrom(DateTime(2026, 1, 2)),
      );
      await source.pause(b);

      final rows = await source.all();

      expect(rows.map((r) => r.rule.id), [a, b]);
      expect(rows.map((r) => r.rule.isActive), [true, false]);
      expect(rows.last.template!.accountId, bank);
    });

    test('is empty with no rules', () async {
      expect(await source.all(), isEmpty);
    });
  });

  group('pause and resume', () {
    test('pause stops the rule and nothing else', () async {
      final id = await createMonthlyRent();
      await source.pause(id);

      final rule = await ruleRow(id);
      expect(rule['is_active'], 0);
      expect(rule['next_due_date'], '2026-02-05');
      expect(await source.due(DateTime(2026, 6)), isEmpty);
    });

    test('resume starts it again from the date given', () async {
      final id = await createMonthlyRent();
      await source.pause(id);
      await source.resume(id, DateTime(2026, 7, 5));

      final rule = await ruleRow(id);
      expect(rule['is_active'], 1);
      expect(rule['next_due_date'], '2026-07-05');
    });

    test('resume refuses a rule with no template (E-36)', () async {
      final id = await createMonthlyRent();
      await db.update(
        'recurring_rules',
        {'template_tx_id': null, 'is_active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );

      await expectLater(
        source.resume(id, DateTime(2026, 7, 5)),
        throwsA(isA<CacheException>()),
      );
      expect((await ruleRow(id))['is_active'], 0);
    });

    test('a missing rule is refused, not ignored', () async {
      await expectLater(source.pause(999), throwsA(isA<CacheException>()));
      await expectLater(
        source.resume(999, DateTime(2026, 7, 5)),
        throwsA(isA<CacheException>()),
      );
    });

    test('both fire the change signal', () async {
      final id = await createMonthlyRent();
      var fired = bus.changes.first;
      await source.pause(id);
      await expectLater(fired, completes);
      fired = bus.changes.first;
      await source.resume(id, DateTime(2026, 7, 5));
      await expectLater(fired, completes);
    });
  });

  group('delete (E-36)', () {
    test('keeps every entry, unlinked and still marked as generated', () async {
      final id = await createMonthlyRent();
      await source.post(
        ruleId: id,
        expectedNextDueDate: DateTime(2026, 2, 5),
        entries: [rentOn(DateTime(2026, 2, 5)).copyWithRule(id)],
        nextDueDate: DateTime(2026, 3, 5),
        ended: false,
        postedAt: DateTime(2026, 2, 5),
      );

      await source.delete(id);

      expect(await count('recurring_rules'), 0);
      final rows = await db.query('transactions', orderBy: 'date ASC');
      expect(rows, hasLength(2));
      expect(rows.map((r) => r['recurring_rule_id']), [null, null]);
      expect(rows.map((r) => r['is_recurring']), [1, 1]);
      // Money that moved stays moved.
      expect(await balance(cash), -2 * 4500000);
    });

    test('a missing rule unlinks nothing and throws', () async {
      final id = await createMonthlyRent();

      await expectLater(source.delete(999), throwsA(isA<CacheException>()));

      final template = (await db.query('transactions')).single;
      expect(template['recurring_rule_id'], id);
    });

    test('fires the change signal', () async {
      final id = await createMonthlyRent();
      final fired = bus.changes.first;
      await source.delete(id);
      await expectLater(fired, completes);
    });
  });

  group('RecurringRuleRepositoryImpl.watchAll over this datasource', () {
    test('emits on listen, and again after any write on the bus', () async {
      final repository = RecurringRuleRepositoryImpl(source);
      final seen = <List<RecurringSeries>>[];
      final sub = repository.watchAll().listen(
        (r) => seen.add(r.getOrElse((f) => fail('$f'))),
      );
      await pumpEventQueue();
      expect(seen.single, isEmpty);

      final id = await createMonthlyRent();
      await pumpEventQueue();
      expect(seen.last.single.rule.id, id);

      // A write from elsewhere on the shared bus — a transaction edit —
      // re-reads the list too.
      await db.update(
        'transactions',
        {'amount_cents': 5000000},
        where: 'recurring_rule_id = ?',
        whereArgs: [id],
      );
      bus.notify();
      await pumpEventQueue();
      expect(seen.last.single.template!.amountCents, 5000000);

      await sub.cancel();
    });
  });

  // ── the catch-up, end to end ──────────────────────────────────────────────

  group('PostDueRecurringTransactions over this datasource', () {
    late PostDueRecurringTransactions postDue;
    // Past, so AddTransaction's future-date rule — on the real clock —
    // never refuses an entry.
    final now = DateTime(2026, 4, 20, 8, 15);

    setUp(() {
      postDue = PostDueRecurringTransactions(
        RecurringRuleRepositoryImpl(source),
        _OpenAccounts(),
      );
    });

    Future<List<String>> datesFor(int ruleId) async => [
      for (final row in await db.query(
        'transactions',
        columns: ['date'],
        where: 'recurring_rule_id = ?',
        whereArgs: [ruleId],
        orderBy: 'date ASC',
      ))
        row['date']! as String,
    ];

    test(
      'posts every missed month once, and a second run posts nothing',
      () async {
        final ruleId = await createMonthlyRent();

        final first = await postDue(now);
        final second = await postDue(now);

        expect(
          first,
          const Right<Failure, RecurringPostingReport>(
            RecurringPostingReport(postedCount: 3, failures: []),
          ),
        );
        expect(
          second,
          const Right<Failure, RecurringPostingReport>(
            RecurringPostingReport.nothing,
          ),
        );
        expect(await datesFor(ruleId), [
          '2026-01-05',
          '2026-02-05',
          '2026-03-05',
          '2026-04-05',
        ]);
        expect((await ruleRow(ruleId))['next_due_date'], '2026-05-05');
        expect(await balance(cash), -4 * 4500000);
      },
    );

    test('two runs racing post each entry once — launch and resume landing '
        'together', () async {
      final ruleId = await createMonthlyRent();

      final results = await Future.wait([postDue(now), postDue(now)]);

      final posted = [
        for (final r in results) r.getOrElse((_) => fail('$r')).postedCount,
      ];
      // One run posts all three; the other either found nothing due or
      // lost the compare-and-set and reported it. Never six.
      expect(posted.reduce((a, b) => a + b), 3);
      expect(await datesFor(ruleId), hasLength(4));
      expect(await balance(cash), -4 * 4500000);
    });

    test('income posts and credits the account (FR-INC-004)', () async {
      final ruleId = await source.create(
        first: TransactionModel(
          accountId: bank,
          categoryId: salary,
          amountCents: 25000000,
          type: TransactionType.income,
          date: DateTime(2026, 3, 25),
        ),
        rule: monthlyFrom(DateTime(2026, 3, 25)),
      );

      await postDue(now);

      expect(await datesFor(ruleId), ['2026-03-25']);
      // Due 2026-04-25, after `now`: only the template so far.
      expect(await balance(bank), 25000000);

      await postDue(DateTime(2026, 4, 25));
      expect(await datesFor(ruleId), ['2026-03-25', '2026-04-25']);
      expect(await balance(bank), 50000000);
    });
  });
}

extension on TransactionModel {
  TransactionModel copyWithRule(int ruleId) => TransactionModel.fromEntity(
    copyWith(recurringRuleId: ruleId, isRecurring: true),
  );
}
