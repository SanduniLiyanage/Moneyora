import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';

void main() {
  group('PlanPeriod', () {
    test('a whole month covers that month once, fully', () {
      final september = PlanPeriod.month(2026, 9);
      // monthOf with day 1 is the same calendar month, whatever the date.
      expect(PlanPeriod.monthOf(DateTime(2026, 9, 17)), september);

      expect(september.from, DateTime(2026, 9));
      expect(september.to, DateTime(2026, 9, 30));
      expect(september.days, 30);
      expect(september.monthCoverage, [
        const MonthCoverage(year: 2026, month: 9, days: 30, fraction: 1.0),
      ]);
      expect(september.months, 1.0);
    });

    test('February is 28 or 29 days and still one month', () {
      expect(PlanPeriod.month(2026, 2).days, 28);
      expect(PlanPeriod.month(2028, 2).days, 29);
      expect(PlanPeriod.month(2028, 2).months, 1.0);
    });

    test('a week across a month boundary is split by the days in each', () {
      final week = PlanPeriod(
        from: DateTime(2026, 11, 28),
        to: DateTime(2026, 12, 4),
      );

      expect(week.days, 7);
      expect(week.monthCoverage.length, 2);
      final (november, december) = (
        week.monthCoverage[0],
        week.monthCoverage[1],
      );
      expect((november.month, november.days), (11, 3));
      expect(november.fraction, closeTo(3 / 30, 1e-12));
      expect((december.month, december.days), (12, 4));
      expect(december.fraction, closeTo(4 / 31, 1e-12));
    });

    test('a year covers twelve whole months', () {
      final year = PlanPeriod(from: DateTime(2027), to: DateTime(2027, 12, 31));

      expect(year.days, 365);
      expect(year.monthCoverage.length, 12);
      expect(year.monthCoverage.every((m) => m.fraction == 1.0), isTrue);
      expect(year.months, 12.0);
    });

    test('days() counts forward from the start, ends included', () {
      final fifteen = PlanPeriod.days(DateTime(2026, 9, 20), 15);

      expect(fifteen.to, DateTime(2026, 10, 4));
      expect(fifteen.days, 15);
      expect(fifteen.monthCoverage.map((m) => m.days), [11, 4]);
    });

    test('a single day is one day of one month', () {
      final day = PlanPeriod(
        from: DateTime(2026, 9, 9),
        to: DateTime(2026, 9, 9),
      );

      expect(day.days, 1);
      expect(day.monthCoverage.single.fraction, closeTo(1 / 30, 1e-12));
    });

    test('the time of day is dropped from both ends', () {
      final a = PlanPeriod(
        from: DateTime(2026, 9, 1, 23, 59),
        to: DateTime(2026, 9, 30, 0, 1),
      );

      expect(a.from, DateTime(2026, 9));
      expect(a.to, DateTime(2026, 9, 30));
    });

    test('the named factories carry their FR-PLN-002 shape', () {
      expect(PlanPeriod.day(DateTime(2026, 9, 9)).type, PlanPeriodType.day);
      expect(PlanPeriod.week(DateTime(2026, 9, 9)).type, PlanPeriodType.week);
      expect(PlanPeriod.month(2026, 9).type, PlanPeriodType.month);
      expect(
        PlanPeriod.monthOf(DateTime(2026, 9, 9)).type,
        PlanPeriodType.month,
      );
      expect(PlanPeriod.year(2026).type, PlanPeriodType.year);
      expect(
        PlanPeriod.days(DateTime(2026, 9, 9), 15).type,
        PlanPeriodType.customDays,
      );
      expect(
        PlanPeriod(from: DateTime(2026, 9), to: DateTime(2026, 9, 30)).type,
        PlanPeriodType.customRange,
      );
    });

    test('the same days as a different shape are a different period', () {
      final range = PlanPeriod(
        from: DateTime(2026, 9),
        to: DateTime(2026, 9, 30),
      );

      expect(range, isNot(PlanPeriod.month(2026, 9)));
    });

    test('a week runs Monday to Sunday by default', () {
      // 9 September 2026 is a Wednesday.
      final week = PlanPeriod.week(DateTime(2026, 9, 9));

      expect(week.from, DateTime(2026, 9, 7));
      expect(week.to, DateTime(2026, 9, 13));
      expect(week.days, 7);
    });

    test('a week can start on Sunday', () {
      final week = PlanPeriod.week(
        DateTime(2026, 9, 9),
        firstWeekday: DateTime.sunday,
      );

      expect(week.from, DateTime(2026, 9, 6));
      expect(week.to, DateTime(2026, 9, 12));
    });

    test('a year is the whole calendar year', () {
      final year = PlanPeriod.year(2027);

      expect(year.from, DateTime(2027));
      expect(year.to, DateTime(2027, 12, 31));
      expect(year.months, 12.0);
    });

    test('an inverted period has no days and no coverage', () {
      final backwards = PlanPeriod(
        from: DateTime(2026, 9, 30),
        to: DateTime(2026, 9),
      );

      expect(backwards.isInverted, isTrue);
      expect(backwards.days, 0);
      expect(backwards.monthCoverage, isEmpty);
      expect(backwards.months, 0);
    });
  });
}
