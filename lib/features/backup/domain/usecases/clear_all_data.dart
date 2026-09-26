import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/backup_repository.dart';

/// Deletes every transaction, account, plan, rule, scan and setting, and
/// opens the app as a fresh install would. FR-SET-009.
///
/// What is written back is the first-launch seed — the Cash account and the
/// default categories — because an app with no account cannot record an
/// expense, and E-22 promises the list is never empty for that reason. The
/// passcode lives in the keychain, not the database, and is left as it is:
/// clearing data is not signing out.
class ClearAllData implements UseCase<Unit, NoParams> {
  /// Creates the use case.
  const ClearAllData(this._repository);

  final BackupRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) => _repository.clearAll();
}
