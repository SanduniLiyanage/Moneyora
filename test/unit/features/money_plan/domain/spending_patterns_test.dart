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
        DailySpending(categoryId: 2, day: DateTime(2026, 6, d), amountCents: c),
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
      // Three weekdays with 22.00 each spent, over 22 weekdays: 3.00 a day.
      final patterns = SpendingPatterns.from(june, [
        for (final d in [3, 10, 17])
          DailySpending(
            day: DateTime(2026, 6, d),
            categoryId: 2,
            amountCents: 2200,
          ),
      ]);

      expect(patterns.week.firstDailyCents, 300);
      expect(patterns.week.secondDailyCents, 0);
      expect(patterns.spendingDays, 3);
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
          DailySpending(
            categoryId: 2,
            day: DateTime(2026, 2, d),
            amountCents: 500,
          ),
      ]);

      expect(patterns.month.secondDailyCents, 500);
      expect(patterns.month.firstDailyCents, 0);
    });

    test('rows outside the window are ignored; one day sums', () {
      DailySpending row(DateTime day, int cents) =>
          DailySpending(day: day, categoryId: 2, amountCents: cents);
      final patterns = SpendingPatterns.from(june, [
        row(DateTime(2026, 5, 31), 99999),
        row(DateTime(2026, 7, 1), 99999),
        row(DateTime(2026, 6, 6, 14), 400),
        row(DateTime(2026, 6, 6), 400),
        row(DateTime(2026, 6, 13), 800),
        row(DateTime(2026, 6, 20), 800),
      ]);

      // 24.00 over June's 8 weekend days.
      expect(patterns.week.secondDailyCents, 300);
      expect(patterns.week.firstDailyCents, 0);
      expect(patterns.spendingDays, 3);
      expect(patterns.leftOut, isEmpty);
    });

    test('too few spending days is not enough history', () {
      final patterns = SpendingPatterns.from(
        june,
        everyDay((d) => d.day < SpendingPatterns.minSpendingDays ? 100 : 0),
      );

      expect(patterns.spendingDays, SpendingPatterns.minSpendingDays - 1);
      expect(patterns.hasEnoughHistory, isFalse);
    });

    test('a rent on the 1st is a bill, not a habit, and is left out', () {
      // Rent on the 1st (category 1) and 10.00 every day on food (category
      // 2). Counted in, the rent would make the first ten days look
      // hundreds of percent dearer; left out, the month is even.
      final patterns = SpendingPatterns.from(june, [
        DailySpending(
          day: DateTime(2026, 6),
          categoryId: 1,
          amountCents: 5000000,
        ),
        ...everyDay((_) => 1000),
      ]);

      expect(patterns.leftOut, {1});
      expect(patterns.month.firstDailyCents, 1000);
      expect(patterns.month.secondDailyCents, 1000);
      expect(patterns.month.lean, isNull);
      expect(patterns.week.lean, isNull);
    });

    test('two days a month is a bill; three is a habit', () {
      final spring = LookbackWindow(months: 3, lastMonth: DateTime(2026, 6));
      List<DailySpending> monthly(int categoryId, List<int> days) => [
        for (final month in [4, 5, 6])
          for (final d in days)
            DailySpending(
              day: DateTime(2026, month, d),
              categoryId: categoryId,
              amountCents: 100,
            ),
      ];

      final patterns = SpendingPatterns.from(spring, [
        ...monthly(1, [1, 15]),
        ...monthly(2, [1, 10, 20]),
      ]);

      expect(patterns.leftOut, {1});
      expect(patterns.spendingDays, 9);
    });

    test('judged over the months it appears in, not the window', () {
      // Three days in one month of three: a habit that month, not a bill
      // spread thin.
      final spring = LookbackWindow(months: 3, lastMonth: DateTime(2026, 6));
      final patterns = SpendingPatterns.from(spring, [
        for (final d in [2, 9, 16])
          DailySpending(
            day: DateTime(2026, 6, d),
            categoryId: 2,
            amountCents: 100,
          ),
      ]);

      expect(patterns.leftOut, isEmpty);
    });

    test('a day of only left-out spending is not a spending day', () {
      final patterns = SpendingPatterns.from(june, [
        DailySpending(day: DateTime(2026, 6), categoryId: 1, amountCents: 900),
        ...everyDay((d) => d.day == 1 ? 0 : 5),
      ]);

      expect(patterns.leftOut, {1});
      expect(patterns.spendingDays, 29);
    });

    test('several months together', () {
      final spring = LookbackWindow(months: 3, lastMonth: DateTime(2026, 6));
      final rows = [
        for (
          var d = spring.from;
          !d.isAfter(spring.to);
          d = DateTime(d.year, d.month, d.day + 1)
        )
          DailySpending(
            categoryId: 2,
            day: d,
            amountCents: isWeekend(d) ? 2000 : 1000,
          ),
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
