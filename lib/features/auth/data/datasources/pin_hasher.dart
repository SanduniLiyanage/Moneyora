import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart' show constantTimeBytesEquality;
import 'package:flutter/foundation.dart';

import '../models/passcode_record.dart';

/// Turns a PIN into a [PasscodeRecord], and checks one against it.
///
/// An interface so the repository's test can hand it something instant. The
/// production one below is deliberately not.
abstract class PinHasher {
  /// A fresh record for [pin], with a new salt.
  Future<PasscodeRecord> hash(String pin);

  /// Whether [pin] derives to [record]'s hash under [record]'s parameters.
  Future<bool> matches(String pin, PasscodeRecord record);
}

/// PBKDF2-HMAC-SHA256 over the PIN and a random 16-byte salt. E-31 §1.
///
/// PBKDF2 rather than Argon2, though `cryptography` ships both: Argon2's
/// advantage is memory-hardness, and a pure-Dart Argon2id at a memory cost
/// that means anything takes seconds on an Android 8 phone — for a search
/// space of at most a million values that NFR-SEC-003's lockout already
/// defends, that is a slow lock screen for no gain. The hash never protects
/// the data (the database key is not derived from the PIN); its job is to
/// not be the bare SHA-256 the DBD specified, and to cost enough per guess
/// that the keychain entry is not a lookup table.
///
/// The derivation runs on a separate isolate through [compute]: a hundred
/// thousand HMAC rounds in Dart take a noticeable fraction of a second on a
/// phone, and the lock screen should not freeze for it. [iterations] is
/// stored in the record, so raising the default later invalidates nothing.
///
/// Comparison is constant-time. Not because timing is a realistic channel
/// against a keychain entry, but because the equality helper costs nothing
/// and the ordinary one would be a thing to explain.
class Pbkdf2PinHasher implements PinHasher {
  /// Creates a hasher. [iterations] applies to new records only; tests pass
  /// a small number so a derivation is instant.
  Pbkdf2PinHasher({this.iterations = defaultIterations, Random? random})
    : _random = random ?? Random.secure();

  /// The count new records are derived with.
  static const int defaultIterations = 100000;

  /// Bytes of salt per record.
  static const int saltLength = 16;

  /// Bytes of derived key per record.
  static const int hashLength = 32;

  /// The count new records are derived with.
  final int iterations;

  final Random _random;

  @override
  Future<PasscodeRecord> hash(String pin) async {
    final salt = List<int>.generate(saltLength, (_) => _random.nextInt(256));
    final hash = await compute(
      _derive,
      _DeriveJob(pin: pin, salt: salt, iterations: iterations),
    );
    return PasscodeRecord(iterations: iterations, salt: salt, hash: hash);
  }

  @override
  Future<bool> matches(String pin, PasscodeRecord record) async {
    final derived = await compute(
      _derive,
      _DeriveJob(pin: pin, salt: record.salt, iterations: record.iterations),
    );
    return constantTimeBytesEquality.equals(derived, record.hash);
  }
}

/// What the derivation isolate is handed: nothing it cannot copy.
class _DeriveJob {
  const _DeriveJob({
    required this.pin,
    required this.salt,
    required this.iterations,
  });

  final String pin;
  final List<int> salt;
  final int iterations;
}

/// Top-level so [compute] can send it to an isolate.
Future<List<int>> _derive(_DeriveJob job) async {
  final kdf = Pbkdf2.hmacSha256(
    iterations: job.iterations,
    bits: Pbkdf2PinHasher.hashLength * 8,
  );
  final key = await kdf.deriveKeyFromPassword(
    password: job.pin,
    nonce: job.salt,
  );
  return key.extractBytes();
}
