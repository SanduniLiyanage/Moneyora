import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/keyword_match.dart';

/// The three-layer categoriser's memory: the seeded keywords and the
/// user's corrections, one table. FR-RCP-007, FR-RCP-015.
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

  /// Teaches the dictionary that [text] means [categoryId]: a user entry
  /// at priority 10, the row FR-RCP-007's Layer 2 reads. FR-RCP-015.
  ///
  /// [text] is stored as one `exact` keyword, normalised (trimmed,
  /// lower-cased, one space between words), not split into words: a
  /// receipt line is a product name and a size, the same shop prints the
  /// same line next time, and guessing which word carried the meaning
  /// would teach that `5kg` means Food. An earlier lesson for the same
  /// text under another category is replaced — the user changed their
  /// mind, and two user rows disagreeing would leave Layer 2 to a
  /// tie-break. Teaching the same thing twice is a no-op.
  Future<Either<Failure, Unit>> learn({
    required String text,
    required int categoryId,
  });
}
