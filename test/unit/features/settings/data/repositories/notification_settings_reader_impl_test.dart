import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/notification_settings.dart';
import 'package:moneyora/features/settings/data/repositories/notification_settings_reader_impl.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';
import 'package:moneyora/features/settings/domain/repositories/settings_repository.dart';

void main() {
  test('projects the notification columns and nothing else', () async {
    final reader = NotificationSettingsReaderImpl(
      _FakeSettings(
        const Right(
          UserSettings(
            theme: AppThemeMode.dark,
            planAnalysisMonths: 12,
            budgetAlertsEnabled: true,
          ),
        ),
      ),
    );

    expect(
      await reader.watch().first,
      const Right<Failure, NotificationSettings>(
        NotificationSettings(budgetAlertsEnabled: true),
      ),
    );
  });

  test('the seeded row reads as the defaults: everything off', () async {
    final reader = NotificationSettingsReaderImpl(
      _FakeSettings(const Right(UserSettings())),
    );

    expect(
      (await reader.watch().first).toNullable(),
      NotificationSettings.defaults,
    );
  });

  test('a failure passes through', () async {
    final reader = NotificationSettingsReaderImpl(
      _FakeSettings(const Left(CacheFailure('locked'))),
    );

    expect(
      await reader.watch().first,
      const Left<Failure, NotificationSettings>(CacheFailure('locked')),
    );
  });
}

class _FakeSettings implements SettingsRepository {
  _FakeSettings(this.value);

  final Either<Failure, UserSettings> value;

  @override
  Stream<Either<Failure, UserSettings>> watch() => Stream.value(value);

  @override
  Future<Either<Failure, UserSettings>> get() async => value;

  @override
  Future<Either<Failure, Unit>> save(UserSettings settings) async =>
      const Right(unit);
}
