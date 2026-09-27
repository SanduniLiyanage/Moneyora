import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// Where a photo attached to an expense comes from. FR-EXP-009.
enum PhotoSource {
  /// The camera, for the receipt in hand.
  camera,

  /// The photo library, for one taken earlier.
  gallery,
}

/// The camera, the photo library and the encrypted vault, seen from the
/// transactions feature. FR-EXP-009, FR-RCP-012.
///
/// The receipt scanner already owns all three — its picker bounds a photo
/// on the way in, and its vault seals it under a key derived from the
/// database's — and rule 4 of `check_architecture.sh` forbids the entry
/// screen importing them. So the seam is here, beside `ReceiptPhotoStore`,
/// and the scanner's data layer fulfils it: a photo attached by hand is
/// kept exactly the way a scanned one is, and a backup carries it the same
/// way, through `transactions.receipt_image_path`.
abstract class ExpensePhotos {
  /// Opens [source], and keeps the photo chosen there sealed in the vault.
  ///
  /// The kept file's path, or null when the user backed out.
  Future<Either<Failure, String?>> pickAndKeep(PhotoSource source);

  /// The photo kept at [path], decrypted. Null when there is no file there.
  Future<Either<Failure, Uint8List?>> read(String path);

  /// Deletes the photo kept at [path], if there is one.
  Future<Either<Failure, Unit>> discard(String path);
}
