import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/analytics/domain/entities/period_selection.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_by_category.dart';

void main() {
  // A Wednesday, deliberately: a week factory that happens to be handed a
  // Monday proves nothing about the offset arithmetic.
  final wednesday = DateTime(2026, 9, 9, 14, 30);

  PeriodSelection on(AnalyticsPeriod period, {DateRange? custom}) =>
      PeriodSelection(period: period, anchor: wednesday, customRange: custom);

  group('DateRange factories', () {
    test('day is that one calendar day at both ends, with no time', () {
      final range = DateRange.day(wednesday);

      expect(range.from, DateTime(2026, 9, 9));
      expect(range.to, DateTime(2026, 9, 9));
    });

    test('week runs Monday to Sunday around the given date', () {
      final range = DateRange.week(wednesday);

      expect(range.from, DateTime(2026, 9, 7));
      expect(range.to, DateTime(2026, 9, 13));
    });

    test('week honours a Sunday start when one is asked for (FR-SET-004)', () {
      final range = DateRange.week(wednesday, firstWeekday: DateTime.sunday);

      expect(range.from, DateTime(2026, 9, 6));
      expect(range.to, DateTime(2026, 9, 12));
    });

    test('week containing its own first day does not step back seven', () {
      final monday = DateTime(2026, 9, 7);

      expect(DateRange.week(monday).from, monday);
    });

    test('year is the first to the last day of that year', () {
      final range = DateRange.year(2026);

      expect(range.from, DateTime(2026));
      expect(range.to, DateTime(2026, 12, 31));
    });

    test('all time brackets every date a row can hold', () {
      final range = DateRange.allTime();

      expect(range.from.isBefore(DateTime(2000, 1, 2)), isTrue);
      expect(range.to.isAfter(DateTime(2100)), isTrue);
      expect(range.isInverted, isFalse);
    });
  });

  group('the range a selection asks for', () {
    test('day', () {
      expect(on(AnalyticsPeriod.day).range, DateRange.day(wednesday));
    });

    test('week', () {
      expect(on(AnalyticsPeriod.week).range, DateRange.week(wednesday));
    });

    test('month', () {
      expect(on(AnalyticsPeriod.month).range, DateRange.month(2026, 9));
    });

    test('year', () {
      expect(on(AnalyticsPeriod.year).range, DateRange.year(2026));
    });

    test('all', () {
      expect(on(AnalyticsPeriod.all).range, DateRange.allTime());
    });

    test('custom is the interval that was picked, not the anchor', () {
      final interval = DateRange(
        from: DateTime(2026, 3, 4),
        to: DateTime(2026, 5, 6),
      );

      expect(on(AnalyticsPeriod.custom, custom: interval).range, interval);
    });

    test('custom with no interval yet falls back to the anchor day', () {
      expect(on(AnalyticsPeriod.custom).range, DateRange.day(wednesday));
    });

    test('all and custom ignore the anchor; the other four do not', () {
      final elsewhere = on(AnalyticsPeriod.all)
          .withAnchor(DateTime(2021, 2, 3));

      expect(elsewhere.range, on(AnalyticsPeriod.all).range);
      expect(
        on(AnalyticsPeriod.month).withAnchor(DateTime(2021, 2, 3)).range,
        DateRange.month(2021, 2),
      );
    });
  });

  group('changing the selection', () {
    test('the default is the calendar month of the day it is', () {
      final selection = PeriodSelection.monthOf(wednesday);

      expect(selection.period, AnalyticsPeriod.month);
      expect(selection.range, DateRange.month(2026, 9));
    });

    test('switching period keeps the anchor, so Week and back is the same '
        'month the user was looking at', () {
      final march = PeriodSelection.monthOf(DateTime(2026, 3, 18));

      final roundTrip = march
          .withPeriod(AnalyticsPeriod.week)
          .withPeriod(AnalyticsPeriod.month);

      expect(roundTrip.range, march.range);
      expect(
        march.withPeriod(AnalyticsPeriod.week).range,
        DateRange.week(DateTime(2026, 3, 18)),
      );
    });

    test('choosing a date re-anchors without changing the period', () {
      final moved = on(AnalyticsPeriod.year).withAnchor(DateTime(2024, 7, 1));

      expect(moved.period, AnalyticsPeriod.year);
      expect(moved.range, DateRange.year(2024));
    });

    test('picking an interval selects the custom period', () {
      final interval = DateRange(
        from: DateTime(2026, 1, 5),
        to: DateTime(2026, 1, 9),
      );

      final custom = on(AnalyticsPeriod.month).withCustomRange(interval);

      expect(custom.period, AnalyticsPeriod.custom);
      expect(custom.range, interval);
    });

    test('a custom interval survives a detour through another period', () {
      final interval = DateRange(
        from: DateTime(2026, 1, 5),
        to: DateTime(2026, 1, 9),
      );

      final back = on(AnalyticsPeriod.month)
          .withCustomRange(interval)
          .withPeriod(AnalyticsPeriod.day)
          .withPeriod(AnalyticsPeriod.custom);

      expect(back.range, interval);
    });
  });

  group('an inverted custom interval', () {
    final backwards = DateRange(
      from: DateTime(2026, 5, 6),
      to: DateTime(2026, 3, 4),
    );

    test('is passed through rather than quietly swapped', () {
      // Correcting it here would turn a mistake into a plausible answer. The
      // use case refuses it instead, which is what the user sees.
      final range = on(AnalyticsPeriod.custom, custom: backwards).range;

      expect(range, backwards);
      expect(range.isInverted, isTrue);
    });

    test('is what GetSpendingByCategory.validate already refuses', () {
      final failure = GetSpendingByCategory.validate(
        on(AnalyticsPeriod.custom, custom: backwards).range,
      );

      expect(failure, isNotNull);
      expect(failure!.message, 'The start of the period is after its end.');
      expect(failure.field, 'from');
    });

    test('no period the picker can build on its own is inverted', () {
      for (final period in AnalyticsPeriod.values) {
        expect(
          GetSpendingByCategory.validate(on(period).range),
          isNull,
          reason: '$period produced a range the use case refuses',
        );
      }
    });
  });
}
