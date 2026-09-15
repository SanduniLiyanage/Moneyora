/// The receipt_scanner layer boundary for the dictionary. Exceptions
/// become failures here and nowhere else, exactly as
/// `MoneyPlanRepositoryImpl` does it.
library;

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/keyword_match.dart';
import '../../domain/repositories/keyword_dictionary_repository.dart';
import '../datasources/keyword_dictionary_local_datasource.dart';

/// Fulfils [KeywordDictionaryRepository] against the local encrypted
/// database.
class KeywordDictionaryRepositoryImpl implements KeywordDictionaryRepository {
  /// Creates a repository over [local].
  const KeywordDictionaryRepositoryImpl(this._local);

  final KeywordDictionaryLocalDataSource _local;

  @override
  Future<Either<Failure, List<KeywordMatch>>> matchesFor(String text) =>
      _attempt(() => _local.matchesFor(text));

  @override
  Future<Either<Failure, Unit>> recordApplied({
    required String text,
    required int categoryId,
  }) => _attempt(() async {
    await _local.recordApplied(text: text, categoryId: categoryId);
    return unit;
  });

  Future<Either<Failure, T>> _attempt<T>(Future<T> Function() body) async {
    try {
      return Right(await body());
    } on AppException catch (e) {
      return Left(_toFailure(e));
    }
  }

  static Failure _toFailure(AppException e) => switch (e) {
    CacheException() => CacheFailure(e.message),
    EncryptionException() => EncryptionFailure(e.message),
    ServerException() => ServerFailure(e.message),
    NetworkException() => const NetworkFailure(),
    OcrException() => OcrFailure(e.message),
    PermissionException() => PermissionFailure(e.message),
  };
}
