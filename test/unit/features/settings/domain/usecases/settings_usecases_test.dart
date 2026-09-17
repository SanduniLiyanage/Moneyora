import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/usecases/usecase.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';
import 'package:moneyora/features/settings/domain/repositories/settings_repository.dart';
import 'package:moneyora/features/settings/domain/usecases/set_theme.dart';
import 'package:moneyora/features/settings/domain/usecases/watch_settings.dart';

/// The settings use cases share one collaborator, and the fake below is most
/// of the code either way — one file, one group per use case, one fake, as
/// `account_usecases_test.dart` does it and for the same reason.
void main() {
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());

  group('SetTheme', () {
    test('changes the theme and nothing else', () async {
      repository.stored = const UserSettings(
        currency: 'USD',
        firstDayOfWeek: DateTime.monday,
        planAnalysisMonths: 12,
      );

      final result = await SetTheme(repository)(AppThemeMode.dark);

      expect(result, const Right<Failure, Unit>(unit));
      expect(
        repository.saved,
        const UserSettings(
          theme: AppThemeMode.dark,
          currency: 'USD',
          firstDayOfWeek: DateTime.monday,
          planAnalysisMonths: 12,
        ),
      );
    });

    test('writes nothing when the row cannot be read', () async {
      repository.failGetWith = const CacheFailure('database is locked');

      final result = await SetTheme(repository)(AppThemeMode.light);

      expect(
        result,
        const Left<Failure, Unit>(CacheFailure('database is locked')),
      );
      expect(repository.saved, isNull);
    });

    test('surfaces a failed write', () async {
      repository.failSaveWith = const CacheFailure('disk full');

      final result = await SetTheme(repository)(AppThemeMode.light);

      expect(result, const Left<Failure, Unit>(CacheFailure('disk full')));
    });
  });

  group('WatchSettings', () {
    test('forwards what the repository emits', () async {
      repository.stored = const UserSettings(theme: AppThemeMode.dark);

      final first = await WatchSettings(repository)(const NoParams()).first;

      expect(
        first,
        const Right<Failure, UserSettings>(
          UserSettings(theme: AppThemeMode.dark),
        ),
      );
    });
  });

  group('AppThemeMode', () {
    test('round-trips through its storage value', () {
      for (final mode in AppThemeMode.values) {
        expect(AppThemeMode.fromStorage(mode.storageValue), mode);
      }
    });

    test('refuses a value the CHECK would refuse', () {
      expect(() => AppThemeMode.fromStorage('sepia'), throwsFormatException);
    });
  });
}

class _FakeRepository implements SettingsRepository {
  UserSettings stored = const UserSettings();
  UserSettings? saved;
  Failure? failGetWith;
  Failure? failSaveWith;

  @override
  Future<Either<Failure, UserSettings>> get() async {
    if (failGetWith case final failure?) return Left(failure);
    return Right(stored);
  }

  @override
  Future<Either<Failure, Unit>> save(UserSettings settings) async {
    if (failSaveWith case final failure?) return Left(failure);
    saved = settings;
    stored = settings;
    return const Right(unit);
  }

  @override
  Stream<Either<Failure, UserSettings>> watch() => Stream.value(Right(stored));
}
