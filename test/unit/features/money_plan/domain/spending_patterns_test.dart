import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/daily_spending_reader.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/spending_patterns.dart';
import 'package:moneyora/features/money_plan/domain/usecases/detect_spending_patterns.dart';

void main() {
  // June 2026: 30 days, starting on a Monday — 22 weekdays, 8 weekend days.
  final june = LookbackWindow(months: 1, lastMonth: DateTime(2026, 6));

  List<DailySpending> everyDay(int Function(DateTime day) cents) => [
    for (var d = 1; d <= 30; d++)
      if (cents(DateTime(2026, 6, d)) case final c when c > 0)
        DailySpending(day: DateTime(2026, 6, d), amountCents: c),
  ];

  bool isWeekend(DateTime d) =>
      d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

  group('PatternComparison', () {
    PatternComparison of(int first, int second) =>
        PatternComparison(firstDailyCents: first, secondDailyCents: second);

    test('25% more is a pattern, exactly at the edge', () {
      expect(of(100, 125).lean, PatternLean.second);
      expect(of(100, 125).percentMore, 25);
      expect(of(125, 100).lean, PatternLean.first);
    });

    test('just under 25% is not', () {
      expect(of(100, 124).lean, isNull);
      expect(of(100, 124).percentMore, isNull);
    });

    test('nothing spent on either side is no pattern', () {
      expect(of(0, 0).lean, isNull);
    });

    test('nothing on one side leans, with no finite percentage', () {
      expect(of(0, 50).lean, PatternLean.second);
      expect(of(0, 50).percentMore, isNull);
    });

    test('the percentage rounds down', () {
      expect(of(300, 100).percentMore, 200);
      expect(of(100, 133).percentMore, 33);
    });
  });

  group('SpendingPatterns.from', () {
    test('the days with nothing spent count toward the average', () {
      // One weekday with 22.00 spent, over 22 weekdays: 1.00 a day.
      final patterns = SpendingPatterns.from(june, [
        DailySpending(day: DateTime(2026, 6, 3), amountCents: 2200),
      ]);

      expect(patterns.week.firstDailyCents, 100);
      expect(patterns.week.secondDailyCents, 0);
      expect(patterns.spendingDays, 1);
    });

    test('an even month has no pattern', () {
      final patterns = SpendingPatterns.from(june, everyDay((_) => 1000));

      expect(patterns.week.lean, isNull);
      expect(patterns.month.lean, isNull);
      expect(patterns.spendingDays, 30);
      expect(patterns.hasEnoughHistory, isTrue);
    });

    test('dearer weekends lean to the weekend', () {
      final patterns = SpendingPatterns.from(
        june,
        everyDay((d) => isWeekend(d) ? 3000 : 1000),
      );

      expect(patterns.week.firstDailyCents, 1000);
      expect(patterns.week.secondDailyCents, 3000);
      expect(patterns.week.lean, PatternLean.second);
      expect(patterns.week.percentMore, 200);
    });

    test('dearer weekdays lean to the weekdays', () {
      final patterns = SpendingPatterns.from(
        june,
        everyDay((d) => isWeekend(d) ? 500 : 1000),
      );

      expect(patterns.week.lean, PatternLean.first);
      expect(patterns.week.percentMore, 100);
    });

    test('the first ten days against the last ten, the middle left out', () {
      final patterns = SpendingPatterns.from(
        june,
        everyDay(
          (d) => switch (d.day) {
            <= 10 => 3000,
            >= 21 => 1000,
            _ => 99999,
          },
        ),
      );

      expect(patterns.month.firstDailyCents, 3000);
      expect(patterns.month.secondDailyCents, 1000);
      expect(patterns.month.lean, PatternLean.first);
    });

    test('the end of a short month is still its last ten days', () {
      final february = LookbackWindow(months: 1, lastMonth: DateTime(2026, 2));
      final patterns = SpendingPatterns.from(february, [
        for (var d = 19; d <= 28; d++)
          DailySpending(day: DateTime(2026, 2, d), amountCents: 500),
      ]);

      expect(patterns.month.secondDailyCents, 500);
      expect(patterns.month.firstDailyCents, 0);
    });

    test('rows outside the window are ignored; one day sums', () {
      final patterns = SpendingPatterns.from(june, [
        DailySpending(day: DateTime(2026, 5, 31), amountCents: 99999),
        DailySpending(day: DateTime(2026, 7, 1), amountCents: 99999),
        DailySpending(day: DateTime(2026, 6, 6, 14), amountCents: 400),
        DailySpending(day: DateTime(2026, 6, 6), amountCents: 400),
      ]);

      expect(patterns.week.secondDailyCents, 100);
      expect(patterns.week.firstDailyCents, 0);
      expect(patterns.spendingDays, 1);
    });

    test('too few spending days is not enough history', () {
      final patterns = SpendingPatterns.from(
        june,
        everyDay((d) => d.day < SpendingPatterns.minSpendingDays ? 100 : 0),
      );

      expect(patterns.spendingDays, SpendingPatterns.minSpendingDays - 1);
      expect(patterns.hasEnoughHistory, isFalse);
    });

    test('several months together', () {
      final spring = LookbackWindow(months: 3, lastMonth: DateTime(2026, 6));
      final rows = [
        for (
          var d = spring.from;
          !d.isAfter(spring.to);
          d = DateTime(d.year, d.month, d.day + 1)
        )
          DailySpending(day: d, amountCents: isWeekend(d) ? 2000 : 1000),
      ];

      final patterns = SpendingPatterns.from(spring, rows);

      expect(patterns.spendingDays, 91);
      expect(patterns.week.firstDailyCents, 1000);
      expect(patterns.week.secondDailyCents, 2000);
    });
  });

  group('DetectSpendingPatterns', () {
    test('reads the window the plan reads, and finds the pattern', () async {
      final reader = _FakeReader(
        Right(everyDay((d) => isWeekend(d) ? 3000 : 1000)),
      );

      final result = await DetectSpendingPatterns(reader)(june);

      expect(reader.asked, (june.from, june.to));
      expect(result.getRight().toNullable()?.week.lean, PatternLean.second);
    });

    test('refuses a window FR-PLN-003 does not allow', () async {
      final reader = _FakeReader(const Right([]));

      final result = await DetectSpendingPatterns(reader)(
        LookbackWindow(months: 25, lastMonth: DateTime(2026, 6)),
      );

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(reader.asked, isNull);
    });

    test('a failure reading passes through', () async {
      final reader = _FakeReader(const Left(CacheFailure()));

      final result = await DetectSpendingPatterns(reader)(june);

      expect(result, const Left<Failure, SpendingPatterns>(CacheFailure()));
    });
  });
}

class _FakeReader implements DailySpendingReader {
  _FakeReader(this.result);

  final Either<Failure, List<DailySpending>> result;
  (DateTime, DateTime)? asked;

  @override
  Future<Either<Failure, List<DailySpending>>> dailySpending({
    required DateTime from,
    required DateTime to,
  }) async {
    asked = (from, to);
    return result;
  }
}
