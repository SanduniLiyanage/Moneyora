import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/ports/calendar_settings.dart';
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

    test('monthOf with day 1 is the calendar month', () {
      expect(DateRange.monthOf(wednesday), DateRange.month(2026, 9));
      expect(DateRange.monthOf(DateTime(2026, 9, 1)), DateRange.month(2026, 9));
      expect(
        DateRange.monthOf(DateTime(2026, 9, 30)),
        DateRange.month(2026, 9),
      );
    });

    test(
      'monthOf with a later start runs to the day before it (FR-SET-004)',
      () {
        // On or after the 25th: this month's 25th to next month's 24th.
        expect(
          DateRange.monthOf(DateTime(2026, 9, 25), firstDay: 25),
          DateRange(from: DateTime(2026, 9, 25), to: DateTime(2026, 10, 24)),
        );
        // Before the 25th: last month's 25th to this month's 24th.
        expect(
          DateRange.monthOf(DateTime(2026, 9, 24), firstDay: 25),
          DateRange(from: DateTime(2026, 8, 25), to: DateTime(2026, 9, 24)),
        );
        // Across a year end.
        expect(
          DateRange.monthOf(DateTime(2027, 1, 3), firstDay: 15),
          DateRange(from: DateTime(2026, 12, 15), to: DateTime(2027, 1, 14)),
        );
      },
    );

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

    test('week, Sunday-first under the schema default calendar', () {
      // CalendarSettings.defaults is the seeded row: first_day_week = 0.
      expect(
        on(AnalyticsPeriod.week).range,
        DateRange.week(wednesday, firstWeekday: DateTime.sunday),
      );
    });

    test('week, cut where the calendar setting says (FR-SET-004)', () {
      expect(
        on(AnalyticsPeriod.week)
            .rangeWith(const CalendarSettings(firstWeekday: DateTime.monday)),
        DateRange.week(wednesday, firstWeekday: DateTime.monday),
      );
    });

    test('month', () {
      expect(on(AnalyticsPeriod.month).range, DateRange.month(2026, 9));
    });

    test('month, starting on the day the calendar setting says', () {
      // The 9th falls before a 25th-start, so it is in the month that
      // began on 25 August.
      expect(
        on(AnalyticsPeriod.month)
            .rangeWith(const CalendarSettings(firstDayOfMonth: 25)),
        DateRange(from: DateTime(2026, 8, 25), to: DateTime(2026, 9, 24)),
      );
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
        DateRange.week(DateTime(2026, 3, 18), firstWeekday: DateTime.sunday),
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

  group('the period before. FR-RPT-006', () {
    PeriodSelection pick(AnalyticsPeriod period, DateTime anchor) =>
        PeriodSelection(period: period, anchor: anchor);

    test('a day, a week and a year step back one of themselves', () {
      final day = DateTime(2026, 3, 1);
      expect(
        pick(AnalyticsPeriod.day, day).previous!.range,
        DateRange.day(DateTime(2026, 2, 28)),
      );
      expect(
        pick(AnalyticsPeriod.week, day).previous!.range,
        // The default calendar's week, which starts on Sunday.
        DateRange.week(DateTime(2026, 2, 22), firstWeekday: DateTime.sunday),
      );
      expect(
        pick(AnalyticsPeriod.year, day).previous!.range,
        DateRange.year(2025),
      );
    });

    test('a month steps to the whole month before, from its last day', () {
      // 31 March back one month is 28 February, not 3 March.
      expect(
        pick(AnalyticsPeriod.month, DateTime(2026, 3, 31)).previous!.range,
        DateRange.month(2026, 2),
      );
      expect(
        pick(AnalyticsPeriod.month, DateTime(2026, 1, 15)).previous!.range,
        DateRange.month(2025, 12),
      );
    });

    test('a month cut on the 25th stays cut on the 25th', () {
      const calendar = CalendarSettings(firstDayOfMonth: 25);
      final now = pick(AnalyticsPeriod.month, DateTime(2026, 9, 26));

      expect(
        now.previous!.rangeWith(calendar),
        DateRange(from: DateTime(2026, 8, 25), to: DateTime(2026, 9, 24)),
      );
    });

    test('a custom range steps back by its own length', () {
      final picked = PeriodSelection.monthOf(DateTime(2026, 9, 1))
          .withCustomRange(
            DateRange(from: DateTime(2026, 9, 10), to: DateTime(2026, 9, 19)),
          );

      expect(
        picked.previous!.range,
        DateRange(from: DateTime(2026, 8, 31), to: DateTime(2026, 9, 9)),
      );
    });

    test('all time has none', () {
      expect(pick(AnalyticsPeriod.all, DateTime(2026, 9, 1)).previous, isNull);
    });
  });
}
