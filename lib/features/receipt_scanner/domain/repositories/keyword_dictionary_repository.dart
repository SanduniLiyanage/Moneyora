import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/keyword_match.dart';

/// The three-layer categoriser's memory: the seeded keywords and the
/// user's corrections, one table. FR-RCP-007, FR-RCP-015.
///
/// FR-RCP-015's learning — writing a correction back as a priority-10
/// user entry — is a later slice's method on this same interface.
abstract class KeywordDictionaryRepository {
  /// Every mapping whose keyword matches [text] by its own match type,
  /// highest priority first (DBD §6.2's lookup, without its `LIMIT 1`:
  /// the categoriser weighs every candidate, not the first).
  ///
  /// [text] is compared lower-cased; the caller need not lower it.
  Future<Either<Failure, List<KeywordMatch>>> matchesFor(String text);

  /// Counts one more use of every mapping that matches [text] and names
  /// [categoryId] — `usage_count`, the DBD's "times this mapping was
  /// applied". FR-RCP-009.
  ///
  /// Called when the user confirms an item under a category, not when the
  /// categoriser suggests one: a suggestion the user overrode was not
  /// applied. A row that matches the text but maps elsewhere is left alone
  /// for the same reason. No rows matching is not an error — the user may
  /// have chosen a category no keyword knows.
  Future<Either<Failure, Unit>> recordApplied({
    required String text,
    required int categoryId,
  });
}
