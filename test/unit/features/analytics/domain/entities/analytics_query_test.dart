import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/period_selection.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';

void main() {
  final august = DateRange(from: DateTime(2026, 8), to: DateTime(2026, 8, 31));
  final september = DateRange.month(2026, 9);

  group('All Accounts', () {
    test('is a null account id, not a sentinel', () {
      final query = AnalyticsQuery(range: august);

      expect(query.accountId, isNull);
      expect(query.isAllAccounts, isTrue);
    });

    test('a specific account is not all accounts', () {
      final query = AnalyticsQuery(range: august, accountId: 3);

      expect(query.isAllAccounts, isFalse);
      expect(query.accountId, 3);
    });
  });

  group('narrowing and widening', () {
    test('picking an account keeps the period', () {
      final query = AnalyticsQuery(range: august).withAccount(7);

      expect(query.accountId, 7);
      expect(query.range, august);
    });

    test('going back to All Accounts keeps the period', () {
      final query = AnalyticsQuery(
        range: august,
        accountId: 7,
      ).withAccount(null);

      expect(query.isAllAccounts, isTrue);
      expect(query.range, august);
    });

    test('changing the period keeps the account', () {
      final query = AnalyticsQuery(
        range: august,
        accountId: 7,
      ).withRange(september);

      expect(query.range, september);
      expect(query.accountId, 7);
    });
  });

  group('as a provider key', () {
    test('two queries over the same period and account are one key', () {
      // The family is keyed on this. Two equal-but-separate keys would run the
      // query twice and cache the answer twice.
      expect(
        AnalyticsQuery(range: DateRange.month(2026, 8), accountId: 2),
        AnalyticsQuery(range: august, accountId: 2),
      );
    });

    test('the account is part of identity, not incidental', () {
      expect(
        AnalyticsQuery(range: august, accountId: 2),
        isNot(AnalyticsQuery(range: august, accountId: 3)),
      );
      expect(
        AnalyticsQuery(range: august, accountId: 2),
        isNot(AnalyticsQuery(range: august)),
      );
    });

    test('so is the period', () {
      expect(
        AnalyticsQuery(range: august, accountId: 2),
        isNot(AnalyticsQuery(range: september, accountId: 2)),
      );
    });
  });

  group('with FR-RPT-002 in front of it', () {
    test('every period shape pairs with an account filter unchanged', () {
      final selection = PeriodSelection.monthOf(DateTime(2026, 9, 9));

      for (final period in AnalyticsPeriod.values) {
        final range = selection.withPeriod(period).range;
        final query = AnalyticsQuery(range: range, accountId: 4);

        expect(query.range, range);
        expect(query.accountId, 4);
      }
    });
  });
}
