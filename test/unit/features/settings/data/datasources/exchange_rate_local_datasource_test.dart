@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/settings/data/datasources/exchange_rate_local_datasource.dart';
import 'package:moneyora/features/settings/data/models/exchange_rate_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Against a real in-memory SQLite, because the claims here are about what
/// the v4 schema does: one row per pair, replaced on re-entry, and the
/// CHECKs turned into exceptions rather than crashes.
void main() {
  sqfliteFfiInit();

  late Database db;
  late ExchangeRateLocalDataSourceImpl rates;

  final when = DateTime.utc(2026, 9, 17, 10);

  ExchangeRateModel rate({
    String from = 'USD',
    String to = 'LKR',
    int micros = 300250000,
  }) => ExchangeRateModel(
    fromCurrency: from,
    toCurrency: to,
    rateMicros: micros,
    updatedAt: when,
  );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
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
    rates = ExchangeRateLocalDataSourceImpl(db);
  });

  tearDown(() async {
    await rates.dispose();
    await db.close();
  });

  test('starts empty', () async {
    expect(await rates.list(), isEmpty);
  });

  test('round-trips a rate', () async {
    await rates.upsert(rate());

    final stored = await rates.list();
    expect(stored.single.toEntity(), rate().toEntity());
    expect(stored.single.updatedAt.isUtc, isTrue);
  });

  test('replaces the rate for a pair rather than adding a second', () async {
    await rates.upsert(rate(micros: 300000000));
    await rates.upsert(rate(micros: 301000000));

    final stored = await rates.list();
    expect(stored, hasLength(1));
    expect(stored.single.rateMicros, 301000000);
  });

  test('lists by pair, and the reverse pair is its own row', () async {
    await rates.upsert(rate(from: 'USD', to: 'LKR'));
    await rates.upsert(rate(from: 'LKR', to: 'USD', micros: 3331));
    await rates.upsert(rate(from: 'EUR', to: 'LKR', micros: 330000000));

    final pairs = (await rates.list())
        .map((r) => '${r.fromCurrency}>${r.toCurrency}')
        .toList();
    expect(pairs, ['EUR>LKR', 'LKR>USD', 'USD>LKR']);
  });

  test('removes a pair, and removing a missing one is not an error', () async {
    await rates.upsert(rate());

    await rates.remove(fromCurrency: 'USD', toCurrency: 'LKR');
    await rates.remove(fromCurrency: 'USD', toCurrency: 'LKR');

    expect(await rates.list(), isEmpty);
  });

  test('the CHECKs arrive as exceptions', () async {
    expect(() => rates.upsert(rate(micros: 0)), throwsA(isA<CacheException>()));
    expect(
      () => rates.upsert(rate(from: 'LKR', to: 'LKR')),
      throwsA(isA<CacheException>()),
    );
  });

  test('announces a write and a real removal, not a no-op one', () async {
    final ticks = <void>[];
    final sub = rates.changes.listen(ticks.add);
    addTearDown(sub.cancel);

    await rates.upsert(rate());
    await rates.remove(fromCurrency: 'USD', toCurrency: 'LKR');
    await rates.remove(fromCurrency: 'USD', toCurrency: 'LKR');
    await Future<void>.delayed(Duration.zero);

    expect(ticks, hasLength(2));
  });
}
