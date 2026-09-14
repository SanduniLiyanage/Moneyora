import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/money_plan/domain/entities/allocation_progress.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';

/// FR-PLN-013's arithmetic, with the clock passed in: the bands, the
/// floored percentage and the projection are all asserted on exact days.
void main() {
  final september = PlanPeriod.month(2026, 9);

  PlanAllocation row({int allocated = 3000000, int spent = 0}) =>
      PlanAllocation(
        categoryId: 1,
        allocatedCents: allocated,
        spentCents: spent,
        confidence: ConfidenceLevel.medium,
      );

  AllocationProgress on(int day, {int allocated = 3000000, int spent = 0}) =>
      AllocationProgress.of(
        row(allocated: allocated, spent: spent),
        september,
        DateTime(2026, 9, day),
      );

  group('percentage', () {
    test('is spent over allocated, in whole percent', () {
      expect(on(15, spent: 1500000).percentUsed, 50);
    });

    test('is floored, so 99.9% never reads as 100%', () {
      // 2,999,999 of 3,000,000 is 99.99…%, still yellow, and must not be
      // labelled with the number that means red.
      expect(on(15, spent: 2999999).percentUsed, 99);
    });

    test('is not capped at 100', () {
      expect(on(15, spent: 4500000).percentUsed, 150);
    });

    test('a zero allocation reads 0% untouched and 100% once spent on', () {
      expect(on(15, allocated: 0).percentUsed, 0);
      expect(on(15, allocated: 0, spent: 1).percentUsed, 100);
    });
  });

  group('status', () {
    test('green below 80%', () {
      expect(on(15, spent: 2399999).status, TrackingStatus.onTrack);
    });

    test('yellow from exactly 80%', () {
      expect(on(15, spent: 2400000).status, TrackingStatus.warning);
    });

    test('yellow up to but not including 100%', () {
      expect(on(15, spent: 2999999).status, TrackingStatus.warning);
    });

    test('red at exactly 100% — nothing left is not on track', () {
      expect(on(15, spent: 3000000).status, TrackingStatus.exceeded);
    });

    test('red past 100%', () {
      expect(on(15, spent: 3000001).status, TrackingStatus.exceeded);
    });

    test('a zero allocation is green untouched and red once spent on', () {
      expect(on(15, allocated: 0).status, TrackingStatus.onTrack);
      expect(on(15, allocated: 0, spent: 1).status, TrackingStatus.exceeded);
    });
  });

  group('projection', () {
    test('extrapolates today\'s rate to the whole period', () {
      // Half the month gone, 1,000,000 spent: the month lands at 2,000,000,
      // 1,000,000 under a 3,000,000 allocation.
      final p = on(15, spent: 1000000);

      expect(p.elapsedDays, 15);
      expect(p.totalDays, 30);
      expect(p.projectedCents, 2000000);
      expect(p.projectedDifferenceCents, -1000000);
    });

    test('counts the first day as one elapsed day', () {
      // Day one: one day's spend times thirty. Not a division by zero.
      final p = on(1, spent: 100000);

      expect(p.elapsedDays, 1);
      expect(p.projectedCents, 3000000);
      expect(p.projectedDifferenceCents, 0);
    });

    test('is a projected overspend when the rate runs ahead', () {
      expect(on(10, spent: 1500000).projectedDifferenceCents, 1500000);
    });

    test('is the spend itself on the last day', () {
      final p = on(30, spent: 2800000);

      expect(p.elapsedDays, 30);
      expect(p.projectedCents, 2800000);
    });

    test('is the spend itself after the period has ended', () {
      final p = AllocationProgress.of(
        row(spent: 2800000),
        september,
        DateTime(2026, 10, 20),
      );

      expect(p.elapsedDays, 30);
      expect(p.projectedCents, 2800000);
    });

    test('is absent before the period has begun', () {
      final p = AllocationProgress.of(
        row(spent: 0),
        september,
        DateTime(2026, 8, 30),
      );

      expect(p.elapsedDays, 0);
      expect(p.projectedCents, isNull);
      expect(p.projectedDifferenceCents, isNull);
    });

    test('ignores the time of day', () {
      final p = AllocationProgress.of(
        row(spent: 1000000),
        september,
        DateTime(2026, 9, 15, 23, 59),
      );

      expect(p.elapsedDays, 15);
    });
  });

  test('remaining is allocated minus spent, negative once exceeded', () {
    expect(on(15, spent: 1000000).remainingCents, 2000000);
    expect(on(15, spent: 3500000).remainingCents, -500000);
  });

  test('is a value: equal readings compare equal', () {
    expect(on(15, spent: 1000000), on(15, spent: 1000000));
    expect(on(15, spent: 1000000), isNot(on(16, spent: 1000000)));
  });
}
