import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/receipt_image_local_datasource.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';

/// Answers as the platform would: a file, nothing, or the exception
/// image_picker throws when a permission is refused.
class _FakePicker implements ReceiptImagePicker {
  XFile? file;
  Exception? throwWith;
  ImageSource? askedFor;
  double? maxWidth;
  int? imageQuality;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    int? imageQuality,
  }) async {
    askedFor = source;
    this.maxWidth = maxWidth;
    this.imageQuality = imageQuality;
    if (throwWith case final e?) throw e;
    return file;
  }
}

void main() {
  late _FakePicker picker;
  late ReceiptImageLocalDataSourceImpl source;

  setUp(() {
    picker = _FakePicker();
    source = ReceiptImageLocalDataSourceImpl(picker);
  });

  test('asks the camera for a bounded photo and returns its path', () async {
    picker.file = XFile('/cache/image_picker/receipt.jpg');

    final path = await source.pick(ReceiptImageSource.camera);

    expect(path, '/cache/image_picker/receipt.jpg');
    expect(picker.askedFor, ImageSource.camera);
    expect(picker.maxWidth, ReceiptImageLocalDataSourceImpl.maxWidth);
    expect(picker.imageQuality, ReceiptImageLocalDataSourceImpl.imageQuality);
  });

  test('maps the gallery source', () async {
    picker.file = XFile('/photos/IMG_0042.jpg');

    await source.pick(ReceiptImageSource.gallery);

    expect(picker.askedFor, ImageSource.gallery);
  });

  test('backing out of the picker is null, not an exception', () async {
    expect(await source.pick(ReceiptImageSource.gallery), isNull);
  });

  test('a refused camera is a PermissionException that says so and offers '
      'the other source', () async {
    picker.throwWith = PlatformException(code: 'camera_access_denied');

    expect(
      () => source.pick(ReceiptImageSource.camera),
      throwsA(
        isA<PermissionException>().having(
          (e) => e.message,
          'message',
          contains('camera'),
        ),
      ),
    );
  });

  test('a refused photo library is a PermissionException', () async {
    picker.throwWith = PlatformException(code: 'photo_access_denied');

    expect(
      () => source.pick(ReceiptImageSource.gallery),
      throwsA(
        isA<PermissionException>().having(
          (e) => e.message,
          'message',
          contains('photos'),
        ),
      ),
    );
  });

  test('any other platform failure is an OcrException naming the source, '
      'with the cause kept', () async {
    final cause = PlatformException(code: 'no_available_camera');
    picker.throwWith = cause;

    expect(
      () => source.pick(ReceiptImageSource.camera),
      throwsA(
        isA<OcrException>()
            .having((e) => e.message, 'message', 'Could not open the camera.')
            .having((e) => e.cause, 'cause', same(cause)),
      ),
    );
  });
}
