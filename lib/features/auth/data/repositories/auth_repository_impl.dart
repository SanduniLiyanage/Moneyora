/// The auth layer boundary. Exceptions become failures here and nowhere
/// else, as `SettingsRepositoryImpl` does it.
library;

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/lockout_state.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_datasource.dart';
import '../datasources/pin_hasher.dart';

/// Fulfils [AuthRepository] over the keychain datasource and a [PinHasher].
///
/// Knows how a PIN is stored and checked; knows nothing about attempts,
/// lockouts or what a wrong answer costs. That is `VerifyPasscode`'s.
class AuthRepositoryImpl implements AuthRepository {
  /// Creates a repository over [local] and [hasher].
  const AuthRepositoryImpl(this._local, this._hasher);

  final AuthLocalDataSource _local;
  final PinHasher _hasher;

  @override
  Future<Either<Failure, bool>> hasPasscode() =>
      _attempt(() async => await _local.readPasscode() != null);

  @override
  Future<Either<Failure, Unit>> setPasscode(String pin) => _attempt(() async {
    final record = await _hasher.hash(pin);
    await _local.writePasscode(record);
    // A new PIN is a new run: whatever the old one had accumulated is not
    // held against it.
    await _local.deleteLockout();
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> clearPasscode() => _attempt(() async {
    await _local.deletePasscode();
    await _local.deleteLockout();
    return unit;
  });

  @override
  Future<Either<Failure, bool>> matchesPasscode(String pin) =>
      _attempt(() async {
        final record = await _local.readPasscode();
        if (record == null) return false;
        return _hasher.matches(pin, record);
      });

  @override
  Future<Either<Failure, LockoutState>> getLockout() =>
      _attempt(() async => await _local.readLockout() ?? LockoutState.none);

  @override
  Future<Either<Failure, Unit>> saveLockout(LockoutState state) =>
      _attempt(() async {
        if (state == LockoutState.none) {
          await _local.deleteLockout();
        } else {
          await _local.writeLockout(state);
        }
        return unit;
      });

  Future<Either<Failure, T>> _attempt<T>(Future<T> Function() body) async {
    try {
      return Right(await body());
    } on AppException catch (e) {
      // The datasource throws only CacheException; anything else is still
      // "the store could not be used", which is what CacheFailure says.
      return Left(CacheFailure(e.message));
    }
  }
}
