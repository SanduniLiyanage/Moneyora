import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// Watches the transactions matching a filter. FR-EXP-006, FR-RPT-002.
///
/// A stream rather than a read, so a list added to on one screen updates on
/// another without either knowing the other exists. The alternative — every
/// screen re-reading when it suspects something changed — is the bug where a
/// total and the rows above it disagree until you navigate away and back.
///
/// The use case adds no logic of its own. It exists so the presentation layer
/// depends on `domain/` rather than reaching for a repository directly, which
/// is what keeps `data/` swappable and the layer check honest. A pass-through
/// use case is not waste; it is the seam.
class WatchTransactions
    implements StreamUseCase<List<Transaction>, TransactionFilter> {
  /// Creates the use case.
  const WatchTransactions(this._repository);

  final TransactionRepository _repository;

  @override
  Stream<Either<Failure, List<Transaction>>> call(TransactionFilter params) =>
      _repository.watch(params);
}
