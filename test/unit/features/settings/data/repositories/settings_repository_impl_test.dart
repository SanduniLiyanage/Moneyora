import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:moneyora/features/settings/data/models/user_settings_model.dart';
import 'package:moneyora/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';

/// The repository translates and nothing else, so these tests are about
/// translation: exceptions becoming failures, models becoming entities, and a
/// watch stream that follows writes and can be cancelled.
void main() {
  late _FakeLocalDataSource local;
  late SettingsRepositoryImpl repository;

  Future<void> settle() async {
    for (var turn = 0; turn < 5; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    local = _FakeLocalDataSource();
    repository = SettingsRepositoryImpl(local);
  });

  tearDown(() => local.dispose());

  test('get hands up an entity, not the model', () async {
    local.stored = const UserSettingsModel(theme: AppThemeMode.dark);

    final result = await repository.get();

    expect(
      result,
      const Right<Failure, UserSettings>(
        UserSettings(theme: AppThemeMode.dark),
      ),
    );
    expect(result.toNullable(), isNot(isA<UserSettingsModel>()));
  });

  test('save writes a model built from the entity', () async {
    final result = await repository.save(
      const UserSettings(theme: AppThemeMode.light, currency: 'USD'),
    );

    expect(result, const Right<Failure, Unit>(unit));
    expect(local.stored.theme, AppThemeMode.light);
    expect(local.stored.currency, 'USD');
  });

  test('a cache exception becomes a cache failure', () async {
    local.failWith = const CacheException('database is locked');

    expect(
      await repository.get(),
      const Left<Failure, UserSettings>(CacheFailure('database is locked')),
    );
    expect(
      await repository.save(const UserSettings()),
      const Left<Failure, Unit>(CacheFailure('database is locked')),
    );
  });

  test('an encryption exception keeps its kind', () async {
    local.failWith = const EncryptionException('no key');

    expect(
      await repository.get(),
      const Left<Failure, UserSettings>(EncryptionFailure('no key')),
    );
  });

  group('watch', () {
    test('emits on listen and again after every write', () async {
      final seen = <Either<Failure, UserSettings>>[];
      final sub = repository.watch().listen(seen.add);
      await settle();

      await repository.save(const UserSettings(theme: AppThemeMode.dark));
      await settle();

      expect(seen, hasLength(2));
      expect(
        seen.last.toNullable(),
        const UserSettings(theme: AppThemeMode.dark),
      );
      await sub.cancel();
    });

    test('stops listening to the datasource once cancelled', () async {
      final sub = repository.watch().listen((_) {});
      await settle();
      expect(local.listened, isTrue);

      await sub.cancel();
      await settle();

      expect(local.listened, isFalse);
    });
  });
}

class _FakeLocalDataSource implements SettingsLocalDataSource {
  UserSettingsModel stored = const UserSettingsModel();
  AppException? failWith;

  final _changes = StreamController<void>.broadcast();

  /// Whether anything is still subscribed to [changes].
  bool get listened => _changes.hasListener;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<UserSettingsModel> read() async {
    if (failWith case final e?) throw e;
    return stored;
  }

  @override
  Future<void> write(UserSettingsModel settings) async {
    if (failWith case final e?) throw e;
    stored = settings;
    _changes.add(null);
  }

  @override
  Future<void> dispose() => _changes.close();
}
