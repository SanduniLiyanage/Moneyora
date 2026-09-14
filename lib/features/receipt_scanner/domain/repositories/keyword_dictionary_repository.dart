import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/keyword_match.dart';

/// The three-layer categoriser's memory: the seeded keywords and the
/// user's corrections, one table. FR-RCP-007, FR-RCP-015.
///
/// Reads only, so far. FR-RCP-015's learning — writing a correction back
/// as a priority-10 user entry — is a later slice's method on this same
/// interface.
abstract class KeywordDictionaryRepository {
  /// Every mapping whose keyword matches [text] by its own match type,
  /// highest priority first (DBD §6.2's lookup, without its `LIMIT 1`:
  /// the categoriser weighs every candidate, not the first).
  ///
  /// [text] is compared lower-cased; the caller need not lower it.
  Future<Either<Failure, List<KeywordMatch>>> matchesFor(String text);
}
