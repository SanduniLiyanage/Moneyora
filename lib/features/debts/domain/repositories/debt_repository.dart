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

  /// Removes the debt with [id].
  Future<Either<Failure, Unit>> delete(int id);
}
