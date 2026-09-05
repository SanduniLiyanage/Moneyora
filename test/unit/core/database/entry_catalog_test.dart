@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/entry_catalog.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The entry screen's pickers come from here, so a mistake shows up as a
/// category that cannot be chosen or an account that is not offered.
///
/// Run against the real seed rather than hand-built rows: what matters is that
/// what ships in `default_seed.dart` arrives in a shape the screen can use.
void main() {
  sqfliteFfiInit();

  late Database db;

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
  });

  tearDown(() => db.close());

  test('reads the seeded categories and the default account', () async {
    final catalog = await readEntryCatalog(db);

    // FR-EXP-003 and FR-INC-002 ship 15 expense and 3 income categories.
    expect(catalog.expenseCategories, hasLength(15));
    expect(catalog.incomeCategories, hasLength(3));
    // FR-ACC-001: starting with no account would make the first expense
    // unrecordable, so one is seeded.
    expect(catalog.accounts, hasLength(1));
    expect(catalog.accounts.single.name, 'Cash');
  });

  test('splits the two kinds without overlap or loss', () async {
    final catalog = await readEntryCatalog(db);

    // The entry screen shows one set or the other. A category in both, or in
    // neither, is a category the user can file the wrong thing under.
    expect(
      catalog.expenseCategories.length + catalog.incomeCategories.length,
      catalog.categories.length,
    );
    final expenseIds = catalog.expenseCategories.map((c) => c.id).toSet();
    final incomeIds = catalog.incomeCategories.map((c) => c.id).toSet();
    expect(expenseIds.intersection(incomeIds), isEmpty);
  });

  test('every category carries what a chip needs to render', () async {
    final catalog = await readEntryCatalog(db);

    for (final category in catalog.categories) {
      expect(category.id, greaterThan(0));
      expect(category.name, isNotEmpty);
      expect(category.icon, isNotEmpty);
      // Parsed as a colour later; a malformed one is a crash at paint time,
      // which is a long way from here.
      expect(category.colorHex, matches(RegExp(r'^#[0-9A-Fa-f]{6}$')));
    }
  });

  test('holds a stable order between reads', () async {
    // A picker that reshuffles itself between launches makes the user hunt for
    // a category they chose yesterday by position.
    final first = await readEntryCatalog(db);
    final second = await readEntryCatalog(db);

    expect(
      first.categories.map((c) => c.id),
      second.categories.map((c) => c.id),
    );
  });

  test('leaves archived accounts out', () async {
    await db.insert('accounts', {
      'user_id': 1,
      'name': 'Old wallet',
      'icon': 'wallet',
      'initial_balance_date': '2026-01-01',
      'is_archived': 1,
      'created_at': '2026-01-01T00:00:00Z',
    });

    final catalog = await readEntryCatalog(db);

    // Archiving exists so an account can stop being offered without deleting
    // the transactions that reference it.
    expect(catalog.accounts.map((a) => a.name), isNot(contains('Old wallet')));
  });

  test('reports the cached balance an account carries', () async {
    await db.update('accounts', {'current_balance_cents': -125000});

    final catalog = await readEntryCatalog(db);

    expect(catalog.accounts.single.balanceCents, -125000);
  });
}
