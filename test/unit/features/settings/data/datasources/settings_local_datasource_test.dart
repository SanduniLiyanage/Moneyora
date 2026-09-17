@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:moneyora/features/settings/data/models/user_settings_model.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Against a real in-memory SQLite, because the claims here are about the
/// schema: that the seed's row reads back as the column defaults, that the
/// CHECK constraints refuse what the entity cannot express anyway, and that
/// the two lock-screen columns are never touched by a preference write.
void main() {
  sqfliteFfiInit();

  late Database db;
  late SettingsLocalDataSourceImpl settings;

  Future<void> seedUser() =>
      db.insert('users', {'id': 1, 'created_at': '2026-01-01T00:00:00Z'});

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          final batch = d.batch();
          // Every version, not v1 alone, so this keeps passing when a later
          // migration touches the users table.
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
    settings = SettingsLocalDataSourceImpl(db);
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
  });

  group('read', () {
    test('returns the schema defaults for a freshly seeded row', () async {
      await seedUser();

      final model = await settings.read();

      // The entity's defaults are the schema's defaults; if either side
      // drifts, this is where it shows.
      expect(model.toEntity(), const UserSettings());
      expect(model.theme, AppThemeMode.system);
    });

    test('throws when the row was never seeded', () async {
      expect(settings.read, throwsA(isA<CacheException>()));
    });
  });

  group('write', () {
    test('round-trips every preference column', () async {
      await seedUser();
      const changed = UserSettingsModel(
        theme: AppThemeMode.dark,
        language: 'si',
        currency: 'USD',
        firstDayOfWeek: DateTime.monday,
        firstDayOfMonth: 25,
        savingsTargetPct: 12.5,
        planAnalysisMonths: 18,
      );

      await settings.write(changed);

      expect((await settings.read()).toEntity(), changed.toEntity());
    });

    test('stores Sunday as the column zero and reads it back', () async {
      // DBD numbers the week from Sunday at zero, Dart from Monday at one.
      await seedUser();

      await settings.write(
        const UserSettingsModel(firstDayOfWeek: DateTime.sunday),
      );

      final row = (await db.query('users')).single;
      expect(row['first_day_week'], 0);
      expect((await settings.read()).firstDayOfWeek, DateTime.sunday);
    });

    test('leaves the lock-screen columns alone', () async {
      await seedUser();
      await db.update('users', {
        'passcode_hash': 'not-a-preference',
        'biometric_enabled': 1,
      });

      await settings.write(const UserSettingsModel(theme: AppThemeMode.light));

      final row = (await db.query('users')).single;
      expect(row['passcode_hash'], 'not-a-preference');
      expect(row['biometric_enabled'], 1);
      expect(row['theme'], 'light');
    });

    test('throws when the row was never seeded, and writes nothing', () async {
      expect(
        () => settings.write(const UserSettingsModel()),
        throwsA(isA<CacheException>()),
      );
      expect(await db.query('users'), isEmpty);
    });

    test('is refused by the CHECK for a lookback outside 1–24', () async {
      await seedUser();

      expect(
        () => settings.write(const UserSettingsModel(planAnalysisMonths: 25)),
        throwsA(isA<CacheException>()),
      );
    });

    test('announces the change', () async {
      await seedUser();
      final ticks = <void>[];
      final sub = settings.changes.listen(ticks.add);
      addTearDown(sub.cancel);

      await settings.write(const UserSettingsModel(theme: AppThemeMode.dark));
      await Future<void>.delayed(Duration.zero);

      expect(ticks, hasLength(1));
    });
  });
}
