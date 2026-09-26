import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/calendar_settings.dart';
import 'package:moneyora/features/settings/data/repositories/calendar_settings_reader_impl.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';
import 'package:moneyora/features/settings/domain/repositories/settings_repository.dart';

void main() {
  test(
    'projects the four Money Plan and calendar columns and nothing else',
    () async {
      final reader = CalendarSettingsReaderImpl(
        _FakeSettings(
          const Right(
            UserSettings(
              theme: AppThemeMode.dark,
              firstDayOfWeek: DateTime.monday,
              firstDayOfMonth: 25,
              planAnalysisMonths: 12,
              savingsTargetPct: 15,
            ),
          ),
        ),
      );

      expect(
        await reader.watch().first,
        const Right<Failure, CalendarSettings>(
          CalendarSettings(
            firstWeekday: DateTime.monday,
            firstDayOfMonth: 25,
            planAnalysisMonths: 12,
            savingsTargetPct: 15,
          ),
        ),
      );
    },
  );

  test('the seeded row reads as the defaults', () async {
    final reader = CalendarSettingsReaderImpl(
      _FakeSettings(const Right(UserSettings())),
    );

    expect(
      (await reader.watch().first).toNullable(),
      CalendarSettings.defaults,
    );
  });

  test('a failure passes through', () async {
    final reader = CalendarSettingsReaderImpl(
      _FakeSettings(const Left(CacheFailure('locked'))),
    );

    expect(
      await reader.watch().first,
      const Left<Failure, CalendarSettings>(CacheFailure('locked')),
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
