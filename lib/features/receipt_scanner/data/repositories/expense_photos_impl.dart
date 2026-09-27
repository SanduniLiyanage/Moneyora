import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/ports/expense_photos.dart';
import '../../domain/entities/receipt_image_source.dart';
import '../datasources/receipt_image_local_datasource.dart';
import '../datasources/receipt_image_vault.dart';

/// Fulfils [ExpensePhotos] with the scanner's own picker and vault.
/// FR-EXP-009.
///
/// The same two datasources a scan uses, so a photo attached by hand is
/// bounded on the way in and sealed on disk exactly as a scanned one is.
/// Exceptions become failures here, as in `ReceiptRepositoryImpl`.
class ExpensePhotosImpl implements ExpensePhotos {
  /// Creates the store over the scanner's [images] and [vault].
  const ExpensePhotosImpl(this._images, this._vault);

  final ReceiptImageLocalDataSource _images;
  final ReceiptImageVault _vault;

  @override
  Future<Either<Failure, String?>> pickAndKeep(PhotoSource source) =>
      _attempt(() async {
        final picked = await _images.pick(switch (source) {
          PhotoSource.camera => ReceiptImageSource.camera,
          PhotoSource.gallery => ReceiptImageSource.gallery,
        });
        return picked == null ? null : _vault.keep(picked);
      });

  @override
  Future<Either<Failure, Uint8List?>> read(String path) =>
      _attempt(() => _vault.read(path));

  @override
  Future<Either<Failure, Unit>> discard(String path) => _attempt(() async {
    await _vault.discard(path);
    return unit;
  });

  Future<Either<Failure, T>> _attempt<T>(Future<T> Function() body) async {
    try {
      return Right(await body());
    } on AppException catch (e) {
      return Left(switch (e) {
        CacheException() => CacheFailure(e.message),
        EncryptionException() => EncryptionFailure(e.message),
        ServerException() => ServerFailure(e.message),
        NetworkException() => const NetworkFailure(),
        OcrException() => OcrFailure(e.message),
        PermissionException() => PermissionFailure(e.message),
      });
    }
  }
}
