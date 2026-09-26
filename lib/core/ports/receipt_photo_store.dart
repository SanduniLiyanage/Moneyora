import 'dart:typed_data';

/// Where kept receipt photos are read and written, for a feature that is
/// not the scanner. FR-RCP-012, FR-BAK-005.
///
/// A backup has to carry the photos a scan kept, and a restore has to put
/// them back under the new phone's key: the kept files are sealed under a
/// key derived from this phone's database key, so the bytes cannot simply
/// be copied across. The backup feature may not import the scanner's data
/// layer (rule 4 of `check_architecture.sh`), so the seam is here, in the
/// shape `core/ports/` already uses; the scanner's vault fulfils it.
abstract class ReceiptPhotoStore {
  /// The photo kept at [path], decrypted. Null when there is no file there.
  ///
  /// Throws what the vault throws when a kept file will not decrypt.
  Future<Uint8List?> read(String path);

  /// Keeps [bytes] as a new photo, sealed under this phone's key, and
  /// returns its path. [extension] is the image's own (`.jpg`), kept in the
  /// name so a plain copy still opens as an image.
  Future<String> keepBytes(Uint8List bytes, {required String extension});

  /// Deletes the kept photo at [path], if there is one. A restore replaces
  /// every row that named a photo, so the photos they named would otherwise
  /// sit sealed in the vault with nothing left to open them for.
  Future<void> discard(String path);
}
