@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/dev_seed.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:moneyora/features/analytics/data/repositories/analytics_repository_impl.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_result.dart';
import 'package:moneyora/features/copilot/domain/usecases/tools/get_spending_by_category_tool.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The Copilot's first tool, wired to the real query, over a real database.
///
/// Every other test of this tool uses a fake reader, which proves the tool's
/// own logic and nothing about whether it is plugged into anything. This one
/// assembles the whole stack the app assembles — datasource, repository, the
/// `core/ports` contract, the tool — and runs it against `dev_seed`'s 24
/// months. If the wiring is wrong, or the query returns a shape the tool
/// cannot read, it fails here rather than on a demo.
///
/// It is also the privacy claim, checked at the only place it can be: the
/// aggregate this tool produces is what the payload builder is later handed.
void main() {
  sqfliteFfiInit();

  late Database db;
  late GetSpendingByCategoryTool tool;

  final end = DateTime(2026, 8, 31);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          final batch = d.batch();
          for (final statement in v1Statements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        },
        version: v1SchemaVersion,
      ),
    );
    await applyDefaultSeed(db);
    await DevSeed.populate(db, endDate: end);

    // Exactly the chain `injection.dart` builds.
    tool = GetSpendingByCategoryTool(
      AnalyticsRepositoryImpl(AnalyticsLocalDataSourceImpl(db)),
    );
  });

  tearDown(() => db.close());

  test('answers "what did I spend in August?" from real rows', () async {
    final result = await tool.execute({
      'from': '2026-08-01',
      'to': '2026-08-31',
    });

    expect(result.isRight(), isTrue);
    result.fold((f) => fail('unexpected failure: $f'), (toolResult) {
      final totals = toolResult.aggregate['totals_cents']! as Map<String, int>;

      expect(totals, isNotEmpty);
      expect(totals.keys, contains('Food'));
      expect(totals.values.every((cents) => cents > 0), isTrue);
    });
  });

  test(
    'the aggregate holds nothing but a period and category totals',
    () async {
      // FR-COP-010 / NFR-PRI-003, checked against real data rather than a fake:
      // no transaction id, no merchant, no note, no account, no colour.
      final result = await tool.execute({
        'from': '2026-08-01',
        'to': '2026-08-31',
      });

      result.fold((f) => fail('unexpected failure: $f'), (toolResult) {
        expect(toolResult.aggregate.keys.toSet(), {
          'from',
          'to',
          'totals_cents',
        });

        final totals =
            toolResult.aggregate['totals_cents']! as Map<String, int>;
        // Keys are category names — every one of them a name the app itself
        // seeded, never a string a user typed.
        expect(totals.keys, everyElement(isA<String>()));
        expect(totals.values, everyElement(isA<int>()));
      });
    },
  );

  test('a month with no history comes back empty, not wrong', () async {
    // Before the seeded window. The agent must be able to say "nothing" and
    // mean it.
    final result = await tool.execute({
      'from': '2020-01-01',
      'to': '2020-01-31',
    });

    result.fold((f) => fail('unexpected failure: $f'), (toolResult) {
      expect(toolResult.aggregate['totals_cents'], isEmpty);
    });
  });

  test(
    'a narrower period totals less than a wider one containing it',
    () async {
      // The property that makes the answers trustworthy: the same query over a
      // longer span can only grow.
      final august = await tool.execute({
        'from': '2026-08-01',
        'to': '2026-08-31',
      });
      final twoMonths = await tool.execute({
        'from': '2026-07-01',
        'to': '2026-08-31',
      });

      int foodIn(Either<Failure, ToolResult> result) {
        final aggregate = result.getRight().toNullable()!.aggregate;
        return (aggregate['totals_cents']! as Map<String, int>)['Food']!;
      }

      expect(foodIn(twoMonths), greaterThan(foodIn(august)));
    },
  );
}
