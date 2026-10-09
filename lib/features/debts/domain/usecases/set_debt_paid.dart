import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/debt.dart';
import '../repositories/debt_repository.dart';

/// Marks a debt paid on a day, or open again. Input to [SetDebtPaid].
class DebtPayment {
  /// Creates the request: [debt] paid on [paidOn], or reopened when null.
  const DebtPayment(this.debt, {required this.paidOn});

  /// The debt, as stored.
  final Debt debt;

  /// The day it was paid; null to open it again.
  final DateTime? paidOn;
}

/// Marks a debt as paid, or as not paid after all. FR-DBT-003.
///
/// Records only that it was paid and when. The money itself moved through
/// an account, and is recorded there as any income or expense is (E-42).
class SetDebtPaid implements UseCase<Unit, DebtPayment> {
  /// Creates the use case.
  const SetDebtPaid(this._repository);

  final DebtRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(DebtPayment params) async {
    if (params.debt.id == null) {
      return const Left(ValidationFailure('That debt has not been saved.'));
    }
    final paid = params.paidOn;
    if (paid != null &&
        DateTime(paid.year, paid.month, paid.day).isBefore(
          DateTime(
            params.debt.incurredOn.year,
            params.debt.incurredOn.month,
            params.debt.incurredOn.day,
          ),
        )) {
      return const Left(
        ValidationFailure('It cannot be paid before the day it started.'),
      );
    }
    return _repository.update(params.debt.withPaidOn(paid));
  }
}
