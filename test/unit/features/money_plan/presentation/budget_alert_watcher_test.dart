import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/local_notifier.dart';
import 'package:moneyora/core/ports/notification_settings.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_evaluation.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_level.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/check_budget_alerts.dart';
import 'package:moneyora/features/money_plan/presentation/providers/budget_alert_watcher.dart';
import 'package:moneyora/features/money_plan/presentation/providers/money_plan_providers.dart';
import 'package:moneyora/injection.dart';

/// The stored levels, with the datasource's compare-and-set rule.
class _Store implements MoneyPlanRepository {
  final Map<int, BudgetAlertLevel> levels = {};
  Failure? failNext;

  @override
  Future<Either<Failure, Set<int>>> recordAlertLevels(
    List<AlertLevelChange> changes,
  ) async {
    if (failNext case final f?) {
      failNext = null;
      return Left(f);
    }
    final moved = <int>{};
    for (final c in changes) {
      if ((levels[c.allocationId] ?? BudgetAlertLevel.none) == c.from) {
        levels[c.allocationId] = c.to;
        moved.add(c.allocationId);
      }
    }
    return Right(moved);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Tray implements LocalNotifier {
  final List<AppNotification> shown = [];

  @override
  Future<Either<Failure, Unit>> show(AppNotification notification) async {
    shown.add(notification);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, bool>> requestPermission() async => const Right(true);
}

void main() {
  late _Store store;
  late _Tray tray;
  late StreamController<MoneyPlan?> plans;
  late StreamController<NotificationSettings> settings;
  late ProviderContainer container;

  setUp(() {
    store = _Store();
    tray = _Tray();
    plans = StreamController();
    settings = StreamController();
    container = ProviderContainer(
      overrides: [
        activePlanProvider.overrideWith((ref) => plans.stream),
        notificationSettingsProvider.overrideWith((ref) => settings.stream),
        checkBudgetAlertsProvider.overrideWith(
          (ref) async => CheckBudgetAlerts(store, tray),
        ),
      ],
    );
    container.listen(budgetAlertWatcherProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await plans.close();
    await settings.close();
  });

  /// The active plan as the datasource would read it now: Food spent as
  /// given, against 10,000, carrying whatever level is stored.
  MoneyPlan read(int spentCents) => MoneyPlan(
    id: 1,
    name: 'September',
    period: PlanPeriod.month(2026, 9),
    totalBudgetCents: 10000,
    isActive: true,
    allocations: [
      PlanAllocation(
        id: 11,
        categoryId: 1,
        categoryName: 'Food',
        allocatedCents: 10000,
        spentCents: spentCents,
        confidence: ConfidenceLevel.medium,
        alertedLevel: store.levels[11] ?? BudgetAlertLevel.none,
      ),
    ],
  );

  Future<void> settle() async {
    await pumpEventQueue();
    await container.read(budgetAlertWatcherProvider.notifier).idle;
    await pumpEventQueue();
  }

  const on = NotificationSettings(budgetAlertsEnabled: true);
  const off = NotificationSettings();

  test('says nothing while alerts are off', () async {
    settings.add(off);
    plans.add(read(9000));
    await settle();

    expect(tray.shown, isEmpty);
    expect(store.levels, isEmpty, reason: 'nothing recorded silently');
  });

  test(
    'announces a crossing once, however often the plan is re-read',
    () async {
      settings.add(on);
      plans.add(read(8500));
      await settle();
      plans
        ..add(read(8600))
        ..add(read(8700));
      await settle();

      expect(tray.shown.map((n) => n.title), ['Food is at 85% of its budget']);
    },
  );

  test('turning alerts on announces what is already true, once', () async {
    settings.add(off);
    plans.add(read(8500));
    await settle();
    expect(tray.shown, isEmpty);

    settings.add(on);
    await settle();

    expect(tray.shown, hasLength(1));
  });

  test('two re-reads taken before either store announce once — the '
      'stale one loses the compare-and-set', () async {
    settings.add(on);
    // Both read with nothing stored, as two quick expenses would be.
    final first = read(8500);
    final second = read(8600);
    plans
      ..add(first)
      ..add(second);
    await settle();

    expect(tray.shown, hasLength(1));
    expect(store.levels[11], BudgetAlertLevel.warning);
  });

  test('warns, falls back, and warns again on the second crossing', () async {
    settings.add(on);
    plans.add(read(8000));
    await settle();
    plans.add(read(5000));
    await settle();
    plans.add(read(8100));
    await settle();

    expect(tray.shown, hasLength(2));
  });

  test('a failed check does not stop the next one', () async {
    settings.add(on);
    store.failNext = const CacheFailure('disk full');
    plans.add(read(8500));
    await settle();
    expect(tray.shown, isEmpty);

    plans.add(read(8500));
    await settle();

    expect(tray.shown, hasLength(1));
  });
}
