import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/domain/entities/credit_card_summary.dart';

/// A card's position, from its balance and its terms. FR-ACC-009, E-43.
void main() {
  final today = DateTime(2026, 10, 9, 18);

  Account card({int balance = -1250000, CreditCardTerms? terms}) => Account(
    name: 'Visa',
    icon: 'card',
    type: AccountType.creditCard,
    initialBalanceDate: DateTime(2026),
    currentBalanceCents: balance,
    creditCard:
        terms ??
        const CreditCardTerms(
          limitCents: 5000000,
          statementDay: 20,
          dueDay: 5,
          aprBasisPoints: 2400,
        ),
  );

  test('what is owed is the balance below zero, and what is left the '
      'limit less it', () {
    final summary = CreditCardSummary.of(card(), today: today);

    expect(summary.owedCents, 1250000);
    expect(summary.availableCents, 3750000);
    expect(summary.utilisationPercent, 25);
  });

  test('a card in credit owes nothing', () {
    final summary = CreditCardSummary.of(card(balance: 30000), today: today);

    expect(summary.owedCents, 0);
    expect(summary.availableCents, 5000000);
    expect(summary.monthlyInterestCents, 0);
  });

  test('over the limit, nothing is left and the share passes 100', () {
    final summary = CreditCardSummary.of(card(balance: -5500000), today: today);

    expect(summary.availableCents, -500000);
    expect(summary.utilisationPercent, 110);
  });

  test('the statement this month when it has not passed, the payment next '
      'month when it has', () {
    final summary = CreditCardSummary.of(card(), today: today);

    expect(summary.nextStatement, DateTime(2026, 10, 20));
    expect(summary.nextDue, DateTime(2026, 11, 5));
    expect(summary.daysUntilDue(today), 27);
  });

  test('a due day that is today is today, and 0 days away', () {
    final summary = CreditCardSummary.of(
      card(terms: const CreditCardTerms(dueDay: 9)),
      today: today,
    );

    expect(summary.nextDue, DateTime(2026, 10, 9));
    expect(summary.daysUntilDue(today), 0);
  });

  test('the 31st in a short month is its last day', () {
    expect(
      CreditCardSummary.nextDayOfMonth(31, DateTime(2026, 2, 10)),
      DateTime(2026, 2, 28),
    );
    expect(
      CreditCardSummary.nextDayOfMonth(31, DateTime(2026, 4, 30)),
      DateTime(2026, 4, 30),
    );
    // Past December's: January of the next year.
    expect(
      CreditCardSummary.nextDayOfMonth(5, DateTime(2026, 12, 6)),
      DateTime(2027, 1, 5),
    );
  });

  test("a month's interest is owed × rate ÷ 12, rounded", () {
    // Rs12,500 at 24% a year: Rs250 a month.
    expect(
      CreditCardSummary.of(card(), today: today).monthlyInterestCents,
      25000,
    );
    // 1 cent at 6% rounds to nothing; 100,001 at 6% to 500.
    expect(CreditCardSummary.monthlyInterest(1, 600), 0);
    expect(CreditCardSummary.monthlyInterest(100001, 600), 500);
  });

  test('a term not entered leaves its figures out', () {
    final summary = CreditCardSummary.of(
      card(terms: CreditCardTerms.none),
      today: today,
    );

    expect(summary.owedCents, 1250000);
    expect(summary.availableCents, isNull);
    expect(summary.utilisationPercent, isNull);
    expect(summary.nextDue, isNull);
    expect(summary.daysUntilDue(today), isNull);
    expect(summary.monthlyInterestCents, isNull);
  });
}
