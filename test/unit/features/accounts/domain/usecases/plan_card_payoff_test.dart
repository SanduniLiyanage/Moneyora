import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/accounts/domain/usecases/plan_card_payoff.dart';

/// Paying a card off a fixed amount a month. FR-ACC-009, E-43.
void main() {
  PayoffRequest request(int owed, int apr, int payment) => PayoffRequest(
    owedCents: owed,
    aprBasisPoints: apr,
    monthlyPaymentCents: payment,
  );

  test('with no interest, the months are the debt over the payment, '
      'rounded up', () {
    expect(
      PlanCardPayoff.plan(request(100000, 0, 30000)),
      const Right<Failure, PayoffPlan>(
        PayoffPlan(months: 4, totalInterestCents: 0),
      ),
    );
  });

  test('each month adds its interest, then the payment comes off', () {
    // Rs1,000 at 12% a year (1% a month), Rs500 a month:
    // 1,000 + 10 − 500 = 510; 510 + 5.10 − 500 = 15.10; 15.10 + 0.15 → 0.
    final plan = PlanCardPayoff.plan(request(100000, 1200, 50000))
        .getOrElse((f) => fail(f.message));

    expect(plan.months, 3);
    expect(plan.totalInterestCents, 1000 + 510 + 15);
  });

  test('nothing owed takes nothing', () {
    expect(
      PlanCardPayoff.plan(request(0, 2400, 1000)),
      const Right<Failure, PayoffPlan>(
        PayoffPlan(months: 0, totalInterestCents: 0),
      ),
    );
  });

  test('a payment that does not cover the interest is refused, in words', () {
    // Rs10,000 at 24% is Rs200 a month in interest.
    final result = PlanCardPayoff.plan(request(1000000, 2400, 20000));

    expect(result.getLeft().toNullable()?.message, contains('interest'));
  });

  test('a plan past fifty years is refused', () {
    // Rs10,000 at 1% a year is Rs8.33 a month in interest; Rs8.34 a month
    // shrinks the debt by about a cent at first, and would take centuries.
    final result = PlanCardPayoff.plan(request(1000000, 100, 834));

    expect(result.getLeft().toNullable()?.message, contains('50 years'));
  });

  test('no payment is refused', () async {
    expect(
      (await const PlanCardPayoff()(request(100000, 2400, 0))).isLeft(),
      isTrue,
    );
  });
}
