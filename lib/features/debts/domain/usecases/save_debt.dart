import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/debt.dart';
import '../repositories/debt_repository.dart';

/// Records a debt, or saves a change to one. FR-DBT-001, FR-DBT-003.
///
/// One use case for both, routed on whether the debt has an id, as
/// `SaveTransactionController` routes an entry: the form is one form, and
/// a caller that has to pick between two is a caller that can pick wrong.
class SaveDebt implements UseCase<Unit, Debt> {
  /// Creates the use case.
  const SaveDebt(this._repository);

  final DebtRepository _repository;

  /// The longest name kept: long enough for "Kasun from accounts", short
  /// enough to stay on one line of the list.
  static const int maxPersonLength = 60;

  @override
  Future<Either<Failure, Unit>> call(Debt params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);
    final debt = Debt(
      id: params.id,
      direction: params.direction,
      person: params.person.trim(),
      amountCents: params.amountCents,
      note: switch (params.note?.trim()) {
        final note? when note.isNotEmpty => note,
        _ => null,
      },
      incurredOn: params.incurredOn,
      dueOn: params.dueOn,
      paidOn: params.paidOn,
    );
    if (debt.id == null) return (await _repository.add(debt)).map((_) => unit);
    return _repository.update(debt);
  }

  /// The reason [debt] cannot be saved, or null when it can. Public and
  /// static so the form can say it beside the field, in these words.
  static ValidationFailure? validate(Debt debt) {
    final person = debt.person.trim();
    if (person.isEmpty) {
      return const ValidationFailure('Say who.', field: 'person');
    }
    if (person.length > maxPersonLength) {
      return const ValidationFailure(
        'That name is too long - $maxPersonLength characters at most.',
        field: 'person',
      );
    }
    if (debt.amountCents <= 0) {
      return const ValidationFailure(
        'Enter an amount greater than zero.',
        field: 'amount',
      );
    }
    if (_day(debt.incurredOn).isAfter(_day(DateTime.now()))) {
      return const ValidationFailure(
        'A debt cannot start in the future.',
        field: 'incurredOn',
      );
    }
    if (debt.dueOn case final due?
        when _day(due).isBefore(_day(debt.incurredOn))) {
      return const ValidationFailure(
        'The due date is before the day it started.',
        field: 'dueOn',
      );
    }
    return null;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}
