import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/monthly_spending_reader.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/usecases/classify_categories.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compute_category_statistics.dart';

/// Answers from a script; the statistics stage beneath the classifier is
/// the real one, so the use case test proves the two compose.
class _FakeReader implements MonthlySpendingReader {
  List<MonthlySpending> rows = const [];
  Failure? failWith;

  @override
  Future<Either<Failure, List<MonthlySpending>>> monthlySpendingByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    if (failWith case final failure?) return Left(failure);
    return Right(rows);
  }
}

/// Twenty-four whole months, September 2024 to August 2026.
final twoYears = LookbackWindow(months: 24, lastMonth: DateTime(2026, 8));

/// Six whole months, March to August 2026 — April inside it.
final halfYear = LookbackWindow(months: 6, lastMonth: DateTime(2026, 8));

CategoryStatistics _stats(List<int> totals, {String name = 'Food'}) =>
    CategoryStatistics.of(
      categoryId: 1,
      name: name,
      monthlyTotalsCents: totals,
      transactionCount: totals.where((t) => t > 0).length,
    );

/// [base] every month of [window], with [spikes] (calendar month → amount)
/// replacing it wherever that month occurs.
List<int> _series(
  LookbackWindow window, {
  required int base,
  Map<int, int> spikes = const {},
}) => [for (final start in window.monthStarts) spikes[start.month] ?? base];

void main() {
  group('Fixed against Variable', () {
    test('a steady series is Fixed', () {
      final stats = _stats(List.filled(6, 4500000), name: 'Bills');

      final c = ClassifyCategories.classify(stats, halfYear);

      expect(c.type, ExpenseType.fixed);
      expect(c.seasonalMonths, isEmpty);
      expect(c.name, 'Bills');
      expect(c.categoryId, 1);
    });

    test('a CV just under 0.15 is Fixed, just over is Variable', () {
      // Two values alternating: CV = sd / mean. For [a, b] repeated, the
      // sample sd of six values is |a-b| / 2 * sqrt(6/5).
      final under = _stats([1000, 1250, 1000, 1250, 1000, 1250]);
      final over = _stats([1000, 1400, 1000, 1400, 1000, 1400]);

      expect(under.coefficientOfVariation, lessThan(0.15));
      expect(over.coefficientOfVariation, greaterThan(0.15));
      expect(
        ClassifyCategories.classify(under, halfYear).type,
        ExpenseType.fixed,
      );
      expect(
        ClassifyCategories.classify(over, halfYear).type,
        ExpenseType.variable,
      );
    });

    test('a noisy series is Variable', () {
      final stats = _stats([2000, 900, 3100, 1500, 2600, 700]);

      expect(
        ClassifyCategories.classify(stats, halfYear).type,
        ExpenseType.variable,
      );
    });

    test('a rising series is Variable — trend is not a class', () {
      final stats = _stats([1000, 1200, 1400, 1600, 1800, 2000], name: 'Car');

      expect(stats.trend, TrendDirection.rising);
      expect(
        ClassifyCategories.classify(stats, halfYear).type,
        ExpenseType.variable,
      );
    });

    test('three rows in two years are classified from those three rows', () {
      // No confidence check here: FR-PLN-010 decides how far to trust it.
      final totals = List.filled(24, 0)
        ..[3] = 200000
        ..[11] = 180000
        ..[21] = 230000;
      final stats = _stats(totals, name: 'Pets');

      final c = ClassifyCategories.classify(stats, twoYears);

      expect(c.type, ExpenseType.variable);
      expect(c.seasonalMonths, isEmpty);
    });
  });

  group('Seasonal (E-07)', () {
    test('a spike in the same month both years, over 24 months', () {
      final stats = _stats(
        _series(twoYears, base: 100000, spikes: {12: 900000}),
        name: 'Gifts',
      );

      final c = ClassifyCategories.classify(stats, twoYears);

      expect(c.type, ExpenseType.seasonal);
      expect(c.seasonalMonths, [12]);
    });

    test('two recurring spikes are both named, ascending', () {
      final stats = _stats(
        _series(twoYears, base: 100000, spikes: {12: 900000, 4: 800000}),
      );

      expect(ClassifyCategories.classify(stats, twoYears).seasonalMonths, [
        4,
        12,
      ]);
    });

    test('never assigned below 24 months, whatever the index says', () {
      // April 2026 is inside the six-month window and eight times the base:
      // the month-of-year index would flag it, and the gate refuses.
      final stats = _stats(
        _series(halfYear, base: 100000, spikes: {4: 800000}),
        name: 'Gifts',
      );

      final c = ClassifyCategories.classify(stats, halfYear);

      expect(c.type, ExpenseType.variable);
      expect(c.seasonalMonths, isEmpty);
      expect(ClassifyCategories.seasonalMonthsOf(stats, halfYear), isEmpty);
    });

    test('23 months is below the gate too', () {
      final window = LookbackWindow(months: 23, lastMonth: DateTime(2026, 8));
      final stats = _stats(_series(window, base: 100000, spikes: {12: 900000}));

      expect(
        ClassifyCategories.classify(stats, window).type,
        ExpenseType.variable,
      );
    });

    test('a spike in one year only does not recur', () {
      final totals = _series(twoYears, base: 100000);
      // December 2025 only — index 3 in a window starting September 2024
      // is December 2024; index 15 is December 2025.
      totals[15] = 900000;
      final stats = _stats(totals);

      final c = ClassifyCategories.classify(stats, twoYears);

      expect(c.type, ExpenseType.variable);
      expect(c.seasonalMonths, isEmpty);
    });

    test('one huge December and one ordinary one do not average into a '
        'cycle', () {
      final totals = _series(twoYears, base: 100000);
      totals[3] = 5000000; // December 2024
      totals[15] = 100000; // December 2025: nothing special
      final stats = _stats(totals);

      // The mean index for December would clear 1.5 on the first year
      // alone; the strict reading refuses it.
      expect(ClassifyCategories.seasonalMonthsOf(stats, twoYears), isEmpty);
    });

    test('a spike at exactly 1.5 times the mean is not over the index', () {
      // Base 100 in 22 months, x in 2: mean = (2200 + 2x) / 24. The spike
      // equals 1.5 × mean when x = 1.5 (2200 + 2x) / 24 → x = 157.14…, so
      // 157 sits just under and 158 just over.
      final under = _stats(_series(twoYears, base: 100, spikes: {12: 157}));
      final over = _stats(_series(twoYears, base: 100, spikes: {12: 158}));

      expect(ClassifyCategories.seasonalMonthsOf(under, twoYears), isEmpty);
      expect(ClassifyCategories.seasonalMonthsOf(over, twoYears), [12]);
    });

    test('statistics over a different span than the window are not '
        'seasonal', () {
      final stats = _stats(List.filled(6, 100));

      expect(ClassifyCategories.seasonalMonthsOf(stats, twoYears), isEmpty);
    });
  });

  group('the use case', () {
    late _FakeReader reader;
    late ClassifyCategories classify;

    setUp(() {
      reader = _FakeReader();
      classify = ClassifyCategories(ComputeCategoryStatistics(reader));
    });

    MonthlySpending row(
      DateTime month, {
      required int categoryId,
      required String name,
      required int cents,
    }) => MonthlySpending(
      categoryId: categoryId,
      name: name,
      month: month,
      amountCents: cents,
      transactionCount: 1,
    );

    test('classifies every category the statistics stage describes', () async {
      reader.rows = [
        for (final start in twoYears.monthStarts) ...[
          row(start, categoryId: 1, name: 'Bills', cents: 4500000),
          row(
            start,
            categoryId: 2,
            name: 'Gifts',
            cents: start.month == 12 ? 900000 : 100000,
          ),
        ],
        row(DateTime(2025, 3), categoryId: 3, name: 'Pets', cents: 200000),
      ];

      final result = await classify(twoYears);

      result.fold((f) => fail('unexpected failure: $f'), (all) {
        final byName = {for (final c in all) c.name: c};
        expect(byName['Bills']!.type, ExpenseType.fixed);
        expect(byName['Gifts']!.type, ExpenseType.seasonal);
        expect(byName['Gifts']!.seasonalMonths, [12]);
        expect(byName['Pets']!.type, ExpenseType.variable);
        // Same order the statistics come in: largest mean first.
        expect(all.map((c) => c.name), ['Bills', 'Gifts', 'Pets']);
      });
    });

    test('the same rows over six months: Gifts is Variable', () async {
      reader.rows = [
        for (final start in halfYear.monthStarts)
          row(
            start,
            categoryId: 2,
            name: 'Gifts',
            cents: start.month == 4 ? 900000 : 100000,
          ),
      ];

      final result = await classify(halfYear);

      result.fold((f) => fail('unexpected failure: $f'), (all) {
        expect(all.single.type, ExpenseType.variable);
      });
    });

    test('refuses a window the statistics stage refuses', () async {
      final result = await classify(
        LookbackWindow(months: 0, lastMonth: DateTime(2026, 8)),
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('should have refused'),
      );
    });

    test('a failure from beneath passes through unchanged', () async {
      reader.failWith = const CacheFailure('disk is full');

      final result = await classify(twoYears);

      expect(
        result,
        const Left<Failure, List<CategoryClassification>>(
          CacheFailure('disk is full'),
        ),
      );
    });
  });
}
