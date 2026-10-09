import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/debt.dart';
import '../repositories/debt_repository.dart';

/// Every debt, open ones first, kept live. FR-DBT-002.
class WatchDebts implements StreamUseCase<List<Debt>, NoParams> {
  /// Creates the use case.
  const WatchDebts(this._repository);

  final DebtRepository _repository;

  @override
  Stream<Either<Failure, List<Debt>>> call(NoParams params) =>
      _repository.watch();
}
