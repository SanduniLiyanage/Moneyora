/// The device's camera and photo library, behind the same kind of seam as
/// the recogniser: a platform channel cannot run in a unit test, so the
/// package sits behind an interface and the datasource over it is tested
/// against a fake.
///
/// Everything here throws [AppException] on failure, per the layer contract
/// in `docs/ARCHITECTURE.md` §3; `ReceiptRepositoryImpl` converts.
library;

import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/receipt_image_source.dart';

/// The slice of `image_picker` this datasource uses.
///
/// An interface for the same reason [TextRecogniser] is one: the real
/// implementation opens a native picker that cannot run in a unit test.
/// [ImagePickerReceiptImagePicker] is the one that ships; a test hands in
/// a fake that returns a path, null, or throws what the platform would.
abstract class ReceiptImagePicker {
  /// Opens the picker for [source] and returns the chosen file, or null
  /// when the user backed out.
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    int? imageQuality,
  });
}

/// The [ReceiptImagePicker] that ships, over `image_picker`.
///
/// Not unit-tested: everything it does is a platform-channel call.
class ImagePickerReceiptImagePicker implements ReceiptImagePicker {
  /// Creates the picker.
  ImagePickerReceiptImagePicker() : _picker = ImagePicker();

  final ImagePicker _picker;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    int? imageQuality,
  }) => _picker.pickImage(
    source: source,
    maxWidth: maxWidth,
    imageQuality: imageQuality,
  );
}

/// A receipt photo from the device. FR-RCP-002.
abstract class ReceiptImageLocalDataSource {
  /// The path of a photo from [source], or null when the user backed out.
  ///
  /// Throws [PermissionException] when the camera or the photo library was
  /// refused, and [OcrException] when the picker failed for any other
  /// reason — the photo is the first thing the scanner reads, and a photo
  /// it could not get is a receipt it could not read.
  Future<String?> pick(ReceiptImageSource source);
}

/// Fulfils [ReceiptImageLocalDataSource] over a [ReceiptImagePicker].
///
/// The photo is bounded on the way in: at most [maxWidth] pixels wide and
/// re-encoded at [imageQuality]. A phone camera's full frame is four times
/// the pixels the recogniser needs for receipt print, and an image that
/// size is what makes the first scan wait — the SRS's 5-second OCR budget
/// (NFR-PER-003) is spent on recognition, not on decoding a photo.
class ReceiptImageLocalDataSourceImpl implements ReceiptImageLocalDataSource {
  /// Creates a datasource over [picker].
  const ReceiptImageLocalDataSourceImpl(this._picker);

  final ReceiptImagePicker _picker;

  /// The longest a photo comes back, in pixels on its wider side.
  static const double maxWidth = 1600;

  /// JPEG quality, 0–100, of the photo as handed on.
  static const int imageQuality = 85;

  @override
  Future<String?> pick(ReceiptImageSource source) async {
    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: switch (source) {
          ReceiptImageSource.camera => ImageSource.camera,
          ReceiptImageSource.gallery => ImageSource.gallery,
        },
        maxWidth: maxWidth,
        imageQuality: imageQuality,
      );
    } on PlatformException catch (e) {
      // image_picker's own codes for a refused permission, on both
      // platforms; anything else is the device failing to open the picker.
      throw switch (e.code) {
        'camera_access_denied' => const PermissionException(
          'Moneyora needs the camera to scan a receipt. Allow it in '
          'Settings, or choose a photo instead.',
        ),
        'photo_access_denied' => const PermissionException(
          'Moneyora needs your photos to pick a receipt. Allow it in '
          'Settings, or take a photo instead.',
        ),
        _ => OcrException('Could not open the ${source.name}.', cause: e),
      };
    }
    return file?.path;
  }
}
