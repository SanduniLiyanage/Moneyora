/// Exceptions thrown by the **data layer only**.
///
/// Repositories catch these at the layer boundary and convert them into
/// [Failure]s. Nothing above `data/` should ever see one of these types.
library;

/// Base for every Moneyora data-layer exception.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' ($cause)'}';
}

/// A local database read/write failed (sqflite/SQLCipher error, constraint
/// violation, corrupt file).
class CacheException extends AppException {
  const CacheException(super.message, {super.cause});
}

/// The encrypted database could not be opened — usually a missing or rotated
/// key in secure storage.
class EncryptionException extends AppException {
  const EncryptionException(super.message, {super.cause});
}

/// A remote call failed (non-2xx, malformed body, timeout).
///
/// Every network call in Moneyora is optional, so callers must treat this as
/// "fall back to on-device behaviour", never as a fatal error.
class ServerException extends AppException {
  const ServerException(super.message, {this.statusCode, super.cause});

  final int? statusCode;
}

/// The device has no usable connection.
class NetworkException extends AppException {
  const NetworkException([super.message = 'No internet connection']);
}

/// On-device OCR could not extract usable text from the image.
class OcrException extends AppException {
  const OcrException(super.message, {super.cause});
}

/// Camera, gallery, or biometric permission was denied.
class PermissionException extends AppException {
  const PermissionException(super.message);
}
