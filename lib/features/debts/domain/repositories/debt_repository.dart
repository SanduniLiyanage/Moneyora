import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/debt.dart';

/// What the debts feature needs from the `debts` table. E-42.
abstract interface class DebtRepository {
  /// Every debt, open ones first, kept live.
  Stream<Either<Failure, List<Debt>>> watch();

  /// Stores a new debt and returns its id.
  Future<Either<Failure, int>> add(Debt debt);

  /// Stores several new debts in one write, all or none, and returns their
  /// ids in order. FR-DBT-004.
  Future<Either<Failure, List<int>>> addAll(List<Debt> debts);

  /// Replaces the stored debt with [debt]'s id.
  Future<Either<Failure, Unit>> update(Debt debt);

  /// Replaces every one of [debts] in one write, all or none: a person
  /// renamed, or settled up, half way is two people, or a net that no
  /// longer adds up. FR-DBT-006.
  Future<Either<Failure, Unit>> updateAll(List<Debt> debts);

  /// Removes the debt with [id].
  Future<Either<Failure, Unit>> delete(int id);

  /// Adds [add], replaces [update] and removes the debts with the ids in
  /// [delete], in one write, all or none, and returns the new ids of [add]
  /// in order. Settling up with a person, and taking it back. FR-DBT-007.
  Future<Either<Failure, List<int>>> batch({
    List<Debt> add = const [],
    List<Debt> update = const [],
    List<int> delete = const [],
  });
}
