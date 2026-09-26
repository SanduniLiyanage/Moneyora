/// The `.mora` file: what a backup's contents look like on disk.
/// FR-BAK-001, FR-BAK-005, NFR-PRT-004, E-08, E-38.
///
/// Throws [AppException] on failure, per the layer contract in
/// `docs/ARCHITECTURE.md` §3; `BackupRepositoryImpl` converts.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../../core/errors/exceptions.dart';

/// Seals a backup's contents under a password, and opens them again.
///
/// ## Why a password, and not the database key
///
/// The database key lives in this phone's keychain and never leaves it, so
/// a backup sealed under it could only be restored onto the phone that made
/// it — which is the one place a backup is not needed. FR-BAK-005 asks for
/// a restore "from any valid Moneyora backup file" on any device, so the
/// key has to come from the user: a password, stretched with
/// PBKDF2-HMAC-SHA256 into an AES-256-GCM key. The same primitives the
/// passcode and the receipt vault already use, from the same package.
///
/// ## The file
///
/// `MORA`, a format byte, the PBKDF2 iteration count (four bytes, big
/// endian), a 16-byte salt, then GCM's nonce, ciphertext and tag as
/// `cryptography` concatenates them. Everything a reader needs to derive the
/// key travels in the header, so raising the iteration count later breaks no
/// file already made. GCM is authenticated: a wrong password, a truncated
/// download and a tampered file all fail to open rather than decoding into
/// rows. Inside is gzip'd JSON — see `BackupLocalDataSource` for its shape.
class BackupCodec {
  /// Creates the codec. [iterations] is PBKDF2's work factor for new files;
  /// tests lower it, since the VM pays it in full on every seal.
  const BackupCodec({this.iterations = defaultIterations});

  /// PBKDF2's work factor for a new backup. The passcode's figure: a
  /// second or so on an Android 8 phone, once per backup, off the UI
  /// isolate.
  static const int defaultIterations = 100000;

  /// The work factor this file seals with.
  final int iterations;

  /// The first four bytes of every backup: "MORA".
  static const List<int> magic = [0x4D, 0x4F, 0x52, 0x41];

  /// The layout after the magic. Raise it when the layout changes.
  static const int formatVersion = 1;

  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int _headerLength = 4 + 1 + 4 + _saltLength;

  /// The most iterations a file is trusted to ask for, so a hostile file
  /// cannot make opening it take an hour.
  static const int _maxIterations = 10000000;

  static final AesGcm _cipher = AesGcm.with256bits();

  /// [contents] as a sealed `.mora` file.
  Future<Uint8List> seal(Map<String, Object?> contents, String password) async {
    final plain = gzip.encode(utf8.encode(jsonEncode(contents)));
    final random = Random.secure();
    final salt = List<int>.generate(_saltLength, (_) => random.nextInt(256));
    final key = await _derive(password, salt, iterations);
    final box = await _cipher.encrypt(
      plain,
      secretKey: key,
      nonce: _cipher.newNonce(),
    );
    return Uint8List.fromList([
      ...magic,
      formatVersion,
      ...(ByteData(4)..setUint32(0, iterations)).buffer.asUint8List(),
      ...salt,
      ...box.concatenation(),
    ]);
  }

  /// The contents of the sealed file [bytes].
  ///
  /// Throws [CacheException] when [bytes] is not a backup this version can
  /// read, and [EncryptionException] when [password] does not open it.
  Future<Map<String, Object?>> open(Uint8List bytes, String password) async {
    if (bytes.length < _headerLength + _nonceLength + _macLength ||
        !_startsWithMagic(bytes)) {
      throw const CacheException('That file is not a Moneyora backup.');
    }
    if (bytes[4] != formatVersion) {
      throw const CacheException(
        'This backup was made by a newer version of Moneyora. Update the '
        'app, then restore it.',
      );
    }
    final work = ByteData.sublistView(bytes, 5, 9).getUint32(0);
    if (work < 1 || work > _maxIterations) {
      throw const CacheException('That file is not a Moneyora backup.');
    }
    final salt = bytes.sublist(9, _headerLength);
    final box = SecretBox.fromConcatenation(
      bytes.sublist(_headerLength),
      nonceLength: _nonceLength,
      macLength: _macLength,
    );

    final List<int> plain;
    try {
      plain = await _cipher.decrypt(
        box,
        secretKey: await _derive(password, salt, work),
      );
    } on SecretBoxAuthenticationError catch (e) {
      throw EncryptionException(
        'That password does not open this backup.',
        cause: e,
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(gzip.decode(plain)));
      if (decoded is! Map<String, Object?>) throw const FormatException();
      return decoded;
    } on FormatException catch (e) {
      throw CacheException('That backup is damaged.', cause: e);
    }
  }

  /// PBKDF2 on its own isolate: pure Dart, and seconds of it would freeze
  /// the screen that asked.
  static Future<SecretKey> _derive(
    String password,
    List<int> salt,
    int iterations,
  ) async {
    final bytes = await Isolate.run(() async {
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: salt);
      return key.extractBytes();
    });
    return SecretKey(bytes);
  }

  static bool _startsWithMagic(Uint8List bytes) {
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}
