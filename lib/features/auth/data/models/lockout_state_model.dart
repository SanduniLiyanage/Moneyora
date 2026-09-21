import 'dart:convert';

import '../../domain/entities/lockout_state.dart';

/// [LockoutState] as the one JSON string the keychain holds for it.
///
/// One string rather than two entries so an attempt is one write: with the
/// count and the expiry stored separately, a crash between the two writes
/// would leave a count without its lockout, or the reverse.
///
/// `{"failed": 5, "until": 1790000000000}` — the expiry in UTC epoch
/// milliseconds, or null while there is none.
abstract final class LockoutStateModel {
  /// The stored form of [state].
  static String encode(LockoutState state) => jsonEncode({
    'failed': state.failedAttempts,
    'until': state.lockedUntil?.toUtc().millisecondsSinceEpoch,
  });

  /// Parses the stored form. Throws [FormatException] when it is not one.
  static LockoutState decode(String stored) {
    final decoded = jsonDecode(stored);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Not a lockout record', stored);
    }
    final failed = decoded['failed'];
    final until = decoded['until'];
    if (failed is! int || failed < 0 || (until != null && until is! int)) {
      throw FormatException('Bad lockout record', stored);
    }
    return LockoutState(
      failedAttempts: failed,
      lockedUntil: until == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(until as int, isUtc: true),
    );
  }
}
