import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';

void main() {
  group('LookbackWindow', () {
    test('spans whole months, inclusive at both ends', () {
      final window = LookbackWindow(months: 6, lastMonth: DateTime(2026, 8));

      expect(window.from, DateTime(2026, 3));
      expect(window.to, DateTime(2026, 8, 31));
      expect(window.monthStarts, [
        DateTime(2026, 3),
        DateTime(2026, 4),
        DateTime(2026, 5),
        DateTime(2026, 6),
        DateTime(2026, 7),
        DateTime(2026, 8),
      ]);
    });

    test('crosses a year boundary by calendar arithmetic', () {
      final window = LookbackWindow(months: 24, lastMonth: DateTime(2026, 8));

      expect(window.from, DateTime(2024, 9));
      expect(window.to, DateTime(2026, 8, 31));
      expect(window.monthStarts.length, 24);
      expect(window.monthStarts.first, DateTime(2024, 9));
    });

    test('ignores the day and time on the last month', () {
      final a = LookbackWindow(months: 3, lastMonth: DateTime(2026, 8, 17, 9));
      final b = LookbackWindow(months: 3, lastMonth: DateTime(2026, 8));

      expect(a, b);
      expect(a.to, DateTime(2026, 8, 31));
    });

    test('before() is the whole months before the given date', () {
      final window = LookbackWindow.before(DateTime(2026, 9, 13));

      expect(window.months, LookbackWindow.defaultMonths);
      expect(window.from, DateTime(2026, 3));
      expect(window.to, DateTime(2026, 8, 31));
    });

    test('before() in January looks back into the previous year', () {
      final window = LookbackWindow.before(DateTime(2027, 1, 2), months: 2);

      expect(window.from, DateTime(2026, 11));
      expect(window.to, DateTime(2026, 12, 31));
    });

    test('indexOf places a month in the window and refuses one outside', () {
      final window = LookbackWindow(months: 6, lastMonth: DateTime(2026, 8));

      expect(window.indexOf(DateTime(2026, 3)), 0);
      expect(window.indexOf(DateTime(2026, 8, 20)), 5);
      expect(window.indexOf(DateTime(2026, 2, 28)), -1);
      expect(window.indexOf(DateTime(2026, 9)), -1);
    });

    test("is valid only inside FR-PLN-003's 1 to 24 months", () {
      final august = DateTime(2026, 8);
      expect(LookbackWindow(months: 1, lastMonth: august).isValid, isTrue);
      expect(LookbackWindow(months: 24, lastMonth: august).isValid, isTrue);
      expect(LookbackWindow(months: 0, lastMonth: august).isValid, isFalse);
      expect(LookbackWindow(months: 25, lastMonth: august).isValid, isFalse);
    });
  });
}
