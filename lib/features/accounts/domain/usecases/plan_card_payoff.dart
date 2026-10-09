import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/credit_card_summary.dart';

/// What to plan: what is owed, at what rate, paid off how fast.
class PayoffRequest extends Equatable {
  /// Creates the request.
  const PayoffRequest({
    required this.owedCents,
    required this.aprBasisPoints,
    required this.monthlyPaymentCents,
  });

  /// What is owed now, in minor units.
  final int owedCents;

  /// The yearly interest rate in hundredths of a percent.
  final int aprBasisPoints;

  /// What would be paid each month.
  final int monthlyPaymentCents;

  @override
  List<Object?> get props => [owedCents, aprBasisPoints, monthlyPaymentCents];
}

/// How long paying [PayoffRequest.monthlyPaymentCents] a month takes, and
/// what it costs.
class PayoffPlan extends Equatable {
  /// Creates the plan.
  const PayoffPlan({required this.months, required this.totalInterestCents});

  /// Payments until nothing is owed; the last may be smaller.
  final int months;

  /// The interest paid along the way, in minor units.
  final int totalInterestCents;

  @override
  List<Object?> get props => [months, totalInterestCents];
}

/// Paying a card off a fixed amount a month: how many months, and how much
/// of it is interest. FR-ACC-009, E-43.
///
/// Each month the month's interest is added to what is owed — a twelfth of
/// the yearly rate, rounded to the minor unit as [CreditCardSummary] rounds
/// it — and then the payment comes off. A simplification of a real card,
/// which charges daily on the statement balance and sets a minimum payment
/// of its own; the screen says it is an estimate. In integers throughout
/// (E-06).
///
/// Decisions:
/// - **A payment that does not cover a month's interest is refused**, in
///   words: the debt would grow for ever, and "never" is not a number of
///   months.
/// - **Fifty years is the limit.** A plan longer than that is refused the
///   same way; the loop is bounded, and so is what a screen can usefully
///   say.
class PlanCardPayoff implements UseCase<PayoffPlan, PayoffRequest> {
  /// Creates the use case. Stateless.
  const PlanCardPayoff();

  /// The longest plan worked out, in months.
  static const int maxMonths = 600;

  @override
  Future<Either<Failure, PayoffPlan>> call(PayoffRequest params) async =>
      plan(params);

  /// The plan for [request], worked out at once. Static so a screen can
  /// answer as the payment is typed.
  static Either<Failure, PayoffPlan> plan(PayoffRequest request) {
    final payment = request.monthlyPaymentCents;
    if (payment <= 0) {
      return const Left(
        ValidationFailure('Enter a payment greater than zero.'),
      );
    }
    if (request.owedCents <= 0) {
      return const Right(PayoffPlan(months: 0, totalInterestCents: 0));
    }
    if (request.aprBasisPoints < 0) {
      return const Left(ValidationFailure('An interest rate is not negative.'));
    }

    final firstInterest = CreditCardSummary.monthlyInterest(
      request.owedCents,
      request.aprBasisPoints,
    );
    if (payment <= firstInterest) {
      return const Left(
        ValidationFailure(
          'That does not cover the interest, so the amount owed would '
          'never go down. Pay more each month.',
        ),
      );
    }

    var owed = request.owedCents;
    var interest = 0;
    var months = 0;
    while (owed > 0) {
      if (months == maxMonths) {
        return const Left(
          ValidationFailure(
            'At that rate it takes more than 50 years. Pay more each month.',
          ),
        );
      }
      final charged = CreditCardSummary.monthlyInterest(
        owed,
        request.aprBasisPoints,
      );
      interest += charged;
      owed += charged;
      owed -= payment < owed ? payment : owed;
      months++;
    }
    return Right(PayoffPlan(months: months, totalInterestCents: interest));
  }
}
