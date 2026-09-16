/// Where a receipt photo is kept once the user confirms it: the app's own
/// documents directory, encrypted. FR-RCP-012, NFR-SEC-002.
///
/// The picker hands back a file in a cache the platform is free to clear,
/// and the SRS asks for the original "stored encrypted and linked to the
/// resulting transaction(s) for future reference". This datasource is the
/// copy out of that cache, the cipher over it, and the two ways back:
/// bytes for a screen, a plain temporary file for the recogniser, which
/// can only open a path.
///
/// Everything here throws [AppException] on failure, per the layer contract
/// in `docs/ARCHITECTURE.md` §3; `ReceiptRepositoryImpl` converts.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../../../core/database/encryption_key_store.dart';
import '../../../../core/errors/exceptions.dart';

/// The kept copy of a receipt photo. FR-RCP-012.
abstract class ReceiptImageVault {
  /// Copies the photo at [sourcePath] into the vault, encrypted, and
  /// returns the kept file's path. The source is left where it was.
  ///
  /// Throws [CacheException] when the source is gone or the copy could not
  /// be written, [EncryptionException] when the key could not be had.
  Future<String> keep(String sourcePath);

  /// Whether [path] names a file this vault wrote — and so one that has to
  /// be read through it.
  bool holds(String path);

  /// The photo at [path] as image bytes: decrypted when [holds] it, read as
  /// it is when not. Null when there is no file there.
  ///
  /// Throws [EncryptionException] when a kept file will not decrypt — it
  /// was altered, or the key is not the one it was written under.
  Future<Uint8List?> read(String path);

  /// Runs [body] over a plain copy of the kept photo at [path], written to
  /// the temporary directory for as long as [body] runs and deleted after,
  /// whatever [body] did. For a reader that opens paths, not bytes.
  ///
  /// Throws [CacheException] when the kept file is gone, and what [read]
  /// throws when it will not decrypt.
  Future<T> withPlainCopy<T>(
    String path,
    Future<T> Function(String plainPath) body,
  );
}

/// Fulfils [ReceiptImageVault] with AES-256-GCM under a key derived from
/// the database's.
///
/// ## The key
///
/// One secret is kept on this phone — the database key in the platform
/// keychain, through [EncryptionKeyStore] — and this vault derives its own
/// from it with HKDF rather than adding a second entry. The same secret
/// still unlocks everything, which is what Sprint 8's restore has to move
/// and what a user has to lose to lose their data; and the bytes the file
/// cipher sees are not the bytes SQLCipher sees, so a weakness found in
/// one primitive's use of them does not hand over the other's. The
/// derivation's `info` is fixed and versioned: change it and every kept
/// photo is unreadable.
///
/// ## The file
///
/// A fixed four-byte magic, then GCM's nonce, ciphertext and tag as
/// `cryptography` concatenates them. GCM rather than CBC because it is
/// authenticated: a file that was altered, truncated or written under
/// another key fails to open, rather than decoding into noise an image
/// widget then fails on with a less useful message. The nonce is fresh per
/// file from the platform's CSPRNG; a repeated nonce under one GCM key is
/// the one thing that breaks it, and a per-file random 96 bits over the
/// number of receipts a person scans in a lifetime does not come close.
///
/// ## The path
///
/// Absolute, which is what the record and the expenses keep and what the
/// history checks the disk with. On Android the app's files directory is
/// stable for the install. On iOS the container's path can change across
/// updates — a known cost of E-19's "compile-verified only", to be settled
/// when the app first runs there, by resolving a relative name against the
/// documents directory on read.
class EncryptedReceiptImageVault implements ReceiptImageVault {
  /// Creates a vault under [keyStore], writing into `receipts/` under the
  /// directory [documents] returns and plain copies under [temporary].
  /// Both are functions so `path_provider` is asked when first needed, not
  /// when `injection.dart` builds the graph.
  EncryptedReceiptImageVault({
    required this._keyStore,
    required this._documents,
    required this._temporary,
  });

  final EncryptionKeyStore _keyStore;
  final Future<Directory> Function() _documents;
  final Future<Directory> Function() _temporary;

  /// The extension a kept file carries; [holds] is this and nothing else.
  static const String extension = '.enc';

  /// The folder under the documents directory.
  static const String folder = 'receipts';

  /// The first four bytes of every kept file: "MRI1", Moneyora receipt
  /// image, format 1.
  static const List<int> magic = [0x4D, 0x52, 0x49, 0x31];

  static const int _nonceLength = 12;
  static const int _macLength = 16;

  /// HKDF's `info`, the domain separator between this key and any other
  /// derived from the same secret. Versioned; see the class comment.
  static const String keyInfo = 'moneyora/receipt-images/v1';

  static final AesGcm _cipher = AesGcm.with256bits();
  Future<SecretKey>? _key;

  Future<SecretKey> get _secretKey => _key ??= _derive();

  Future<SecretKey> _derive() async {
    final String root;
    try {
      root = await _keyStore.getOrCreateKey();
    } on Exception catch (e) {
      _key = null;
      throw EncryptionException(
        'Could not unlock the receipt photos.',
        cause: e,
      );
    }
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(utf8.encode(root)),
      info: utf8.encode(keyInfo),
    );
  }

  @override
  bool holds(String path) => path.endsWith(extension);

  @override
  Future<String> keep(String sourcePath) async {
    final source = File(sourcePath);
    final Uint8List plain;
    try {
      plain = await source.readAsBytes();
    } on IOException catch (e) {
      throw CacheException('The photo is no longer on this phone.', cause: e);
    }

    final box = await _cipher.encrypt(
      plain,
      secretKey: await _secretKey,
      nonce: _cipher.newNonce(),
    );
    final sealed = Uint8List.fromList([...magic, ...box.concatenation()]);

    try {
      final dir = Directory(p.join((await _documents()).path, folder));
      await dir.create(recursive: true);
      final kept = File(
        p.join(
          dir.path,
          '${_randomName()}${p.extension(sourcePath)}$extension',
        ),
      );
      await kept.writeAsBytes(sealed, flush: true);
      return kept.path;
    } on IOException catch (e) {
      throw CacheException('Could not keep the receipt photo.', cause: e);
    }
  }

  @override
  Future<Uint8List?> read(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on IOException catch (e) {
      throw CacheException('Could not read the receipt photo.', cause: e);
    }
    if (!holds(path)) return bytes;
    return _open(bytes);
  }

  @override
  Future<T> withPlainCopy<T>(
    String path,
    Future<T> Function(String plainPath) body,
  ) async {
    final plain = await read(path);
    if (plain == null) {
      throw const CacheException('The photo is no longer on this phone.');
    }
    final copy = File(
      p.join(
        (await _temporary()).path,
        '${_randomName()}${p.extension(p.withoutExtension(path))}',
      ),
    );
    try {
      await copy.writeAsBytes(plain, flush: true);
    } on IOException catch (e) {
      throw CacheException('Could not open the receipt photo.', cause: e);
    }
    try {
      return await body(copy.path);
    } finally {
      if (copy.existsSync()) await copy.delete();
    }
  }

  Future<Uint8List> _open(Uint8List sealed) async {
    const head = 4;
    if (sealed.length < head + _nonceLength + _macLength ||
        !_startsWithMagic(sealed)) {
      throw const EncryptionException('That is not a kept receipt photo.');
    }
    final box = SecretBox.fromConcatenation(
      sealed.sublist(head),
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    try {
      return Uint8List.fromList(
        await _cipher.decrypt(box, secretKey: await _secretKey),
      );
    } on SecretBoxAuthenticationError catch (e) {
      throw EncryptionException(
        'The receipt photo could not be unlocked.',
        cause: e,
      );
    }
  }

  static bool _startsWithMagic(Uint8List bytes) {
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// 128 random bits as hex. Not a secret — the file's name — but from
  /// the CSPRNG anyway so two files cannot collide on a clock.
  static String _randomName() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
