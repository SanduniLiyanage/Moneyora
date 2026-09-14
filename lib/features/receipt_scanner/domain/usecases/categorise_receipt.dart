import 'dart:math' as math;

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/categorised_receipt.dart';
import '../entities/category_suggestion.dart';
import '../entities/keyword_match.dart';
import '../entities/parsed_receipt.dart';
import '../repositories/keyword_dictionary_repository.dart';

/// A category and a confidence for every item on a parsed receipt, by the
/// SRS's three layers. FR-RCP-007.
///
/// The fifth stage of the pipeline (SDD §7.2): after the parser, before
/// the review screen. Each item's name is looked up in the dictionary
/// once; the merchant's name is looked up once for the whole receipt.
/// SDD §7.2's formula, `keyword_score + history_bonus + merchant_bias`,
/// is applied per candidate category and the highest wins.
///
/// Decisions the SRS and SDD do not make:
/// - **The keyword score is the match's kind plus its priority.** An exact
///   match starts at [exactBase], a prefix at [startsWithBase], a
///   substring at [containsBase]; each adds twice the row's priority, so a
///   seed entry (priority 5) scores 90 / 75 / 65 and a user's (10) 100 /
///   85 / 75 before the bonus. Priority is what the DBD orders the lookup
///   by, and here it is worth points rather than only a tie-break, so the
///   user's correction outranks the seed's keyword on the same text.
/// - **Layer 2 is decisive, not merely favoured.** The SDD stores
///   corrections in `keyword_dictionary` with `is_user_defined = 1`, so a
///   match on one is Layer 2 without a second lookup — and when any such
///   row matches, only such rows are candidates. The SRS says *reuse* that
///   mapping; a seed keyword with the merchant bias behind it must not
///   outvote what the user said about this very text. The row's score
///   adds [historyBonus] so the confidence says who decided: a user
///   `contains` reads 95, a user `exact` 100.
/// - **Layer 3 is the dictionary's verdict on the merchant.** The seed
///   already maps `pharmacy` to Health and `restaurant` to Eating Out, so
///   a merchant's category is whatever the merchant's name matches best —
///   no second list of merchant words to keep in step with the seed, and
///   a user's `keells → Food` extends it. That category gains
///   [merchantBias] on every item; an item nothing matched is suggested
///   the merchant's category at exactly [merchantBias], which is the low
///   confidence FR-RCP-011 exists to badge.
/// - **Per category, the best keyword counts, not the sum.** `rice` and
///   `basmati` both saying Food is one piece of evidence with two names;
///   summing would let a category with many weak keywords beat one strong
///   one.
/// - **Ties go to the longer keyword**, then to the dictionary's own
///   order. `water bill` is more specific than `water`, and a receipt
///   line that holds both was about the bill.
/// - **Nothing is written.** `usage_count` counts mappings *applied*, and
///   a suggestion is not applied until the user confirms it (FR-RCP-009);
///   the confirm step owns that write, beside FR-RCP-015's learning.
///
/// Scores are capped at 100, the SRS's scale.
class CategoriseReceipt implements UseCase<CategorisedReceipt, ParsedReceipt> {
  /// Creates the use case over the dictionary.
  const CategoriseReceipt(this._dictionary);

  final KeywordDictionaryRepository _dictionary;

  /// Score for a keyword equal to the whole text, before priority.
  static const int exactBase = 80;

  /// Score for a keyword the text starts with, before priority.
  static const int startsWithBase = 65;

  /// Score for a keyword found anywhere in the text, before priority.
  static const int containsBase = 55;

  /// Points per unit of a row's priority (1–10).
  static const int priorityWeight = 2;

  /// Layer 2: added when the matching row is the user's own.
  static const int historyBonus = 20;

  /// Layer 3: added to the merchant's category on every item.
  static const int merchantBias = 20;

  @override
  Future<Either<Failure, CategorisedReceipt>> call(ParsedReceipt params) async {
    KeywordMatch? merchant;
    if (params.merchantName case final name?) {
      final matches = await _dictionary.matchesFor(name);
      switch (matches) {
        case Left(value: final failure):
          return Left(failure);
        case Right(value: final found):
          merchant = bestOf(found);
      }
    }

    final items = <CategorisedItem>[];
    for (final item in params.items) {
      final matches = await _dictionary.matchesFor(item.name);
      switch (matches) {
        case Left(value: final failure):
          return Left(failure);
        case Right(value: final found):
          items.add(
            CategorisedItem(
              item: item,
              suggestion: suggest(
                found,
                merchantCategoryId: merchant?.categoryId,
                merchantCategoryName: merchant?.categoryName,
              ),
            ),
          );
      }
    }

    return Right(
      CategorisedReceipt(
        receipt: params,
        items: items,
        merchantCategoryId: merchant?.categoryId,
        merchantCategoryName: merchant?.categoryName,
      ),
    );
  }

  /// The score one match earns on its own: kind, priority, and the
  /// history bonus when it is the user's.
  static int scoreOf(KeywordMatch match) {
    final base = switch (match.matchType) {
      KeywordMatchType.exact => exactBase,
      KeywordMatchType.startsWith => startsWithBase,
      KeywordMatchType.contains => containsBase,
    };
    return base +
        priorityWeight * match.priority +
        (match.isUserDefined ? historyBonus : 0);
  }

  /// The strongest of [matches], or null when there are none: the highest
  /// [scoreOf], then the longer keyword, then the first given.
  ///
  /// Static so a test can state the rule without a repository beneath it.
  static KeywordMatch? bestOf(List<KeywordMatch> matches) {
    KeywordMatch? best;
    var bestScore = -1;
    for (final match in matches) {
      final score = scoreOf(match);
      if (score > bestScore ||
          (score == bestScore && match.keyword.length > best!.keyword.length)) {
        best = match;
        bestScore = score;
      }
    }
    return best;
  }

  /// One item's suggestion from its [matches] and the merchant's category.
  ///
  /// Static so a test can state the rules without a repository beneath
  /// them.
  static CategorySuggestion suggest(
    List<KeywordMatch> matches, {
    int? merchantCategoryId,
    String? merchantCategoryName,
  }) {
    // Layer 2 first: the user's rows, when any matched, are the only
    // candidates.
    final taught = matches.where((m) => m.isUserDefined).toList();
    final candidates = taught.isEmpty ? matches : taught;

    // The best match per category — Food once, however many of its
    // keywords the text holds.
    final bestByCategory = <int, KeywordMatch>{};
    for (final match in candidates) {
      final held = bestByCategory[match.categoryId];
      if (held == null || bestOf([held, match]) == match) {
        bestByCategory[match.categoryId] = match;
      }
    }

    KeywordMatch? winner;
    var winning = -1;
    for (final match in bestByCategory.values) {
      var score = scoreOf(match);
      if (match.categoryId == merchantCategoryId) score += merchantBias;
      if (score > winning ||
          (score == winning && match.keyword.length > winner!.keyword.length)) {
        winner = match;
        winning = score;
      }
    }

    if (winner != null) {
      return CategorySuggestion(
        categoryId: winner.categoryId,
        categoryName: winner.categoryName,
        confidence: math.min(winning, 100),
        source: winner.isUserDefined
            ? SuggestionSource.userHistory
            : SuggestionSource.keyword,
      );
    }
    if (merchantCategoryId != null) {
      return CategorySuggestion(
        categoryId: merchantCategoryId,
        categoryName: merchantCategoryName,
        confidence: merchantBias,
        source: SuggestionSource.merchant,
      );
    }
    return CategorySuggestion.none;
  }
}
