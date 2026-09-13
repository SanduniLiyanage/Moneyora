import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/analytics/domain/entities/spending_calendar.dart';

void main() {
  group('SpendingCalendarQuery', () {
    test('takes the month the anchor falls in', () {
      final query = SpendingCalendarQuery(anchor: DateTime(2026, 9, 9));

      expect(query.year, 2026);
      expect(query.month, 9);
      expect(query.accountId, isNull);
      expect(query, const SpendingCalendarQuery.of(2026, 9));
    });
  });

  group('SpendingCalendar', () {
    SpendingCalendar calendar(List<int> amounts) =>
        SpendingCalendar(year: 2026, month: 9, amountsCents: amounts);

    test('the ceiling is the largest day in the month', () {
      final c = calendar([0, 100, 500, 0, 250]);

      expect(c.maxCents, 500);
      expect(c.totalCents, 850);
      expect(c.isEmpty, isFalse);
      expect(c.dayCount, 5);
    });

    test('a quiet month is empty with a zero ceiling', () {
      final c = calendar([0, 0, 0]);

      expect(c.isEmpty, isTrue);
      expect(c.maxCents, 0);
      expect(c.levelOf(1), 0);
    });

    test('the largest day is always the top level, whatever its size', () {
      expect(calendar([1]).levelOf(1), SpendingCalendar.levels);
      expect(calendar([9999999]).levelOf(1), SpendingCalendar.levels);
    });

    test('levels split the range from nothing to the largest day evenly', () {
      // Max 1000: (0,200]=1, (200,400]=2, (400,600]=3, (600,800]=4,
      // (800,1000]=5.
      final c = calendar([0, 1, 200, 201, 400, 600, 601, 800, 801, 1000]);

      expect(
        [for (var d = 1; d <= 10; d++) c.levelOf(d)],
        [0, 1, 1, 2, 2, 3, 4, 4, 5, 5],
      );
    });

    test('amountOn is 1-based, like a calendar', () {
      final c = calendar([10, 20, 30]);

      expect(c.amountOn(1), 10);
      expect(c.amountOn(3), 30);
    });
  });
}
