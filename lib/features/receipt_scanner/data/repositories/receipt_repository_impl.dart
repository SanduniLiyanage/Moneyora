/// The receipt_scanner layer boundary for the scanner and its records.
/// Exceptions become failures here and nowhere else, exactly as
/// `KeywordDictionaryRepositoryImpl` does it.
library;

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/receipt_image_source.dart';
import '../../domain/entities/receipt_scan.dart';
import '../../domain/entities/recognised_text.dart';
import '../../domain/repositories/receipt_repository.dart';
import '../datasources/ocr_local_datasource.dart';
import '../datasources/receipt_image_local_datasource.dart';
import '../datasources/receipt_scan_local_datasource.dart';
import '../models/receipt_scan_model.dart';

/// Fulfils [ReceiptRepository] against the device's picker, the on-device
/// recogniser and the local encrypted database.
class ReceiptRepositoryImpl implements ReceiptRepository {
  /// Creates a repository over [ocr] for reading, [scans] for keeping and
  /// [images] for the photo itself.
  const ReceiptRepositoryImpl(this._ocr, this._scans, this._images);

  final OcrLocalDataSource _ocr;
  final ReceiptScanLocalDataSource _scans;
  final ReceiptImageLocalDataSource _images;

  @override
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source) =>
      _attempt(() => _images.pick(source));

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) =>
      _attempt(() => _ocr.recognise(imagePath));

  @override
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan) =>
      _attempt(() => _scans.insert(ReceiptScanModel.fromEntity(scan)));

  @override
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory() =>
      _attempt(_scans.listAll);

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
