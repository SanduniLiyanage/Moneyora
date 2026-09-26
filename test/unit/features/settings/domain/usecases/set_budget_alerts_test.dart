import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/local_notifier.dart';
import 'package:moneyora/features/settings/domain/entities/user_settings.dart';
import 'package:moneyora/features/settings/domain/repositories/settings_repository.dart';
import 'package:moneyora/features/settings/domain/usecases/set_budget_alerts.dart';

void main() {
  late _FakeRepository repository;
  late _FakeNotifier notifier;
  late SetBudgetAlerts setBudgetAlerts;

  setUp(() {
    repository = _FakeRepository();
    notifier = _FakeNotifier();
    setBudgetAlerts = SetBudgetAlerts(repository, notifier);
  });

  test('starts off, as the column does', () {
    expect(const UserSettings().budgetAlertsEnabled, isFalse);
  });

  group('turning on', () {
    test('asks for the permission, then stores it and nothing else', () async {
      repository.stored = const UserSettings(
        currency: 'USD',
        planAnalysisMonths: 12,
      );

      final result = await setBudgetAlerts(true);

      expect(result, const Right<Failure, Unit>(unit));
      expect(notifier.asked, 1);
      expect(
        repository.saved,
        const UserSettings(
          currency: 'USD',
          planAnalysisMonths: 12,
          budgetAlertsEnabled: true,
        ),
      );
    });

    test('stores nothing when the permission is refused, and says where '
        'it is now', () async {
      notifier.grant = false;

      final result = await setBudgetAlerts(true);

      expect(
        result,
        const Left<Failure, Unit>(
          PermissionFailure(SetBudgetAlerts.refusedMessage),
        ),
      );
      expect(repository.saved, isNull);
    });

    test(
      'passes a failed permission request through, storing nothing',
      () async {
        notifier.failWith = const PermissionFailure('plugin missing');

        final result = await setBudgetAlerts(true);

        expect(
          result,
          const Left<Failure, Unit>(PermissionFailure('plugin missing')),
        );
        expect(repository.saved, isNull);
      },
    );

    test('surfaces a failed write', () async {
      repository.failSaveWith = const CacheFailure('disk full');

      final result = await setBudgetAlerts(true);

      expect(result, const Left<Failure, Unit>(CacheFailure('disk full')));
    });
  });

  group('turning off', () {
    test('asks nothing and stores it', () async {
      repository.stored = const UserSettings(budgetAlertsEnabled: true);

      final result = await setBudgetAlerts(false);

      expect(result, const Right<Failure, Unit>(unit));
      expect(notifier.asked, 0);
      expect(repository.saved?.budgetAlertsEnabled, isFalse);
    });

    test('writes nothing when the row cannot be read', () async {
      repository.failGetWith = const CacheFailure('database is locked');

      final result = await setBudgetAlerts(false);

      expect(
        result,
        const Left<Failure, Unit>(CacheFailure('database is locked')),
      );
      expect(repository.saved, isNull);
    });
  });
}

class _FakeNotifier implements LocalNotifier {
  bool grant = true;
  Failure? failWith;
  int asked = 0;

  @override
  Future<Either<Failure, bool>> requestPermission() async {
    asked++;
    if (failWith case final f?) return Left(f);
    return Right(grant);
  }

  @override
  Future<Either<Failure, Unit>> show(AppNotification notification) =>
      throw UnimplementedError();

  // Scheduling (FR-SET-006) is not exercised here; a call fails loudly.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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
