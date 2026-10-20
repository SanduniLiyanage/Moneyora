import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/debt_person.dart';
import '../repositories/debt_repository.dart';
import 'save_debt.dart';

/// [person], to be called [to]. Input to [RenamePerson].
class PersonRename extends Equatable {
  /// Creates the request.
  const PersonRename(this.person, {required this.to});

  /// The person as the list groups them, every record included.
  final DebtPerson person;

  /// The new name.
  final String to;

  @override
  List<Object?> get props => [person, to];
}

/// Renames a person on every one of their records at once. FR-DBT-006,
/// E-47.
///
/// Also how two spellings of one person become one: renaming "Nimal P." to
/// "Nimal", someone already listed, puts the two together, because people
/// are grouped by name (FR-DBT-005). The screen asks before it does that;
/// nothing is ever put together without the user saying so. The records
/// themselves are unchanged but for the name, and all of them change or
/// none does.
class RenamePerson implements UseCase<Unit, PersonRename> {
  /// Creates the use case.
  const RenamePerson(this._repository);

  final DebtRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(PersonRename params) async {
    final failure = validate(params.to);
    if (failure != null) return Left(failure);
    final name = params.to.trim();
    final changed = [
      for (final debt in params.person.records)
        if (debt.person != name) debt.withPerson(name),
    ];
    if (changed.isEmpty) return const Right(unit);
    return _repository.updateAll(changed);
  }

  /// The reason [name] cannot be given, or null when it can: the rules a
  /// debt's name is saved under ([SaveDebt.validate]). Public and static so
  /// the dialog can say it beside the field.
  static ValidationFailure? validate(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const ValidationFailure('Say who.', field: 'person');
    }
    if (trimmed.length > SaveDebt.maxPersonLength) {
      return const ValidationFailure(
        'That name is too long - ${SaveDebt.maxPersonLength} characters at '
        'most.',
        field: 'person',
      );
    }
    return null;
  }
}
