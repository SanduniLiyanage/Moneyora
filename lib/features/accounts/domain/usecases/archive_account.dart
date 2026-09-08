import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/account_repository.dart';

/// What to archive, and which way. Input to [ArchiveAccount].
class ArchiveParams {
  /// Creates the parameters.
  const ArchiveParams({required this.accountId, this.archived = true});

  /// The account to hide, or restore.
  final int accountId;

  /// True to archive, false to bring it back.
  final bool archived;
}

/// Hides an account without losing its history. FR-ACC-004.
///
/// This is the answer to "I closed that bank account". The transactions stay,
/// so every past total the user has already seen still adds up, and the
/// account stops cluttering the pickers. Deleting would rewrite history.
class ArchiveAccount implements UseCase<Unit, ArchiveParams> {
  /// Creates the use case.
  const ArchiveAccount(this._repository);

  final AccountRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(ArchiveParams params) async {
    if (!params.archived) {
      return _repository.setArchived(params.accountId, archived: false);
    }

    final accounts = await _repository.list(includeArchived: true);

    return accounts.match(Left.new, (all) async {
      // Archiving the last usable account leaves nowhere to record a
      // transaction, and the entry screen with no account to default to - a
      // dead end reached through a control that looks harmless.
      final remaining = all.where(
        (a) => !a.isArchived && a.id != params.accountId,
      );
      if (remaining.isEmpty) {
        return const Left(
          ValidationFailure(
            'This is your only account. Add another before archiving it.',
          ),
        );
      }

      return _repository.setArchived(params.accountId, archived: true);
    });
  }
}
