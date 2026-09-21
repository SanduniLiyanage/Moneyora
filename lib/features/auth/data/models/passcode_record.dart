import 'dart:convert';

import 'package:equatable/equatable.dart';

/// What is stored for a passcode: the derivation, never the PIN. E-31 §1.
///
/// Serialised in the PHC string format —
/// `$pbkdf2-sha256$i=100000$<salt>$<hash>`, both parts base64 — so the
/// parameters travel with the hash. A record made at 100,000 iterations
/// still verifies after the default is raised, because verification reads
/// the count from the record rather than from a constant, and the raise can
/// then be applied at the next successful unlock rather than by asking
/// everyone to set their PIN again.
///
/// The DBD's `passcode_hash TEXT — "SHA-256 hash of PIN"` is superseded, not
/// used: a bare hash over a 10,000-value space is reversible about as fast
/// as it can be read, and the column has no salt beside it. That column and
/// `biometric_enabled` stay in the schema, empty.
class PasscodeRecord extends Equatable {
  /// Creates a record.
  const PasscodeRecord({
    required this.iterations,
    required this.salt,
    required this.hash,
  });

  /// The one algorithm identifier this app writes or reads.
  static const String algorithm = 'pbkdf2-sha256';

  /// PBKDF2 iteration count the [hash] was derived with.
  final int iterations;

  /// Per-passcode random salt.
  final List<int> salt;

  /// The derived key.
  final List<int> hash;

  /// The stored form.
  String encode() =>
      '\$$algorithm\$i=$iterations\$${base64.encode(salt)}\$'
      '${base64.encode(hash)}';

  /// Parses the stored form.
  ///
  /// Throws [FormatException] for anything this app would not have written —
  /// another algorithm, a missing part, a count that is not a number.
  static PasscodeRecord decode(String stored) {
    final parts = stored.split(r'$');
    // A leading '$' gives an empty first element.
    if (parts.length != 5 || parts[0].isNotEmpty) {
      throw FormatException('Not a passcode record', stored);
    }
    if (parts[1] != algorithm) {
      throw FormatException('Unknown passcode algorithm', parts[1]);
    }
    if (!parts[2].startsWith('i=')) {
      throw FormatException('Missing iteration count', parts[2]);
    }
    final iterations = int.tryParse(parts[2].substring(2));
    if (iterations == null || iterations < 1) {
      throw FormatException('Bad iteration count', parts[2]);
    }
    return PasscodeRecord(
      iterations: iterations,
      salt: base64.decode(parts[3]),
      hash: base64.decode(parts[4]),
    );
  }

  @override
  List<Object?> get props => [iterations, salt, hash];
}
