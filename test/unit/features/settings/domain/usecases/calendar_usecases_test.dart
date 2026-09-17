import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';
import 'package:moneyora/features/settings/domain/repositories/settings_repository.dart';
import 'package:moneyora/features/settings/domain/usecases/set_first_day_of_month.dart';
import 'package:moneyora/features/settings/domain/usecases/set_first_day_of_week.dart';
import 'package:moneyora/features/settings/domain/usecases/set_plan_analysis_months.dart';

/// The three calendar settings, one fake. Each is SetTheme's shape with one
/// rule of its own; the rules are what is tested.
void main() {
  late _FakeSettings settings;

  setUp(() => settings = _FakeSettings());

  group('SetFirstDayOfWeek', () {
    test('accepts Sunday and Monday, and changes nothing else', () async {
      settings.stored = const UserSettings(currency: 'USD');

      expect(
        await SetFirstDayOfWeek(settings)(DateTime.monday),
        const Right<Failure, Unit>(unit),
      );
      expect(
        settings.saved,
        const UserSettings(currency: 'USD', firstDayOfWeek: DateTime.monday),
      );

      await SetFirstDayOfWeek(settings)(DateTime.sunday);
      expect(settings.saved?.firstDayOfWeek, DateTime.sunday);
    });

    test('refuses any other day, in a sentence, and writes nothing', () async {
      final result = await SetFirstDayOfWeek(settings)(DateTime.wednesday);

      expect(
        result,
        const Left<Failure, Unit>(
          ValidationFailure(
            'A week starts on Sunday or Monday.',
            field: 'firstDayOfWeek',
          ),
        ),
      );
      expect(settings.saved, isNull);
      expect(SetFirstDayOfWeek.validate(0)?.field, 'firstDayOfWeek');
      expect(SetFirstDayOfWeek.validate(8)?.field, 'firstDayOfWeek');
    });
  });

  group('SetFirstDayOfMonth', () {
    test('accepts 1 through 28', () async {
      for (final day in [1, 15, 28]) {
        expect(
          await SetFirstDayOfMonth(settings)(day),
          const Right<Failure, Unit>(unit),
        );
        expect(settings.saved?.firstDayOfMonth, day);
      }
    });

    test('refuses a day every month does not have', () {
      expect(SetFirstDayOfMonth.validate(0)?.field, 'firstDayOfMonth');
      expect(
        SetFirstDayOfMonth.validate(29)?.message,
        'Choose a day from 1 to 28, so every month has it.',
      );
      expect(SetFirstDayOfMonth.validate(31), isNotNull);
    });
  });

  group('SetPlanAnalysisMonths', () {
    test('accepts 1 through 24', () async {
      for (final months in [1, 6, 24]) {
        expect(
          await SetPlanAnalysisMonths(settings)(months),
          const Right<Failure, Unit>(unit),
        );
        expect(settings.saved?.planAnalysisMonths, months);
      }
    });

    test('refuses outside FR-PLN-003\'s range', () {
      expect(SetPlanAnalysisMonths.validate(0)?.field, 'planAnalysisMonths');
      expect(
        SetPlanAnalysisMonths.validate(25)?.message,
        'Choose between 1 and 24 months.',
      );
    });

    test('writes nothing when the row cannot be read', () async {
      settings.failGetWith = const CacheFailure('database is locked');

      final result = await SetPlanAnalysisMonths(settings)(12);

      expect(result.isLeft(), isTrue);
      expect(settings.saved, isNull);
    });
  });
}

class _FakeSettings implements SettingsRepository {
  UserSettings stored = const UserSettings();
  UserSettings? saved;
  Failure? failGetWith;

  @override
  Future<Either<Failure, UserSettings>> get() async {
    if (failGetWith case final failure?) return Left(failure);
    return Right(stored);
  }

  @override
  Future<Either<Failure, Unit>> save(UserSettings settings) async {
    saved = settings;
    stored = settings;
    return const Right(unit);
  }

  @override
  Stream<Either<Failure, UserSettings>> watch() => Stream.value(Right(stored));
}
