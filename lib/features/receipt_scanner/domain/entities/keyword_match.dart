import 'package:equatable/equatable.dart';

/// How a dictionary keyword is compared with a line of text. FR-RCP-007.
///
/// The `keyword_dictionary.match_type` check constraint, as an enum.
enum KeywordMatchType { exact, contains, startsWith }

/// One `keyword_dictionary` row that matched a piece of text. FR-RCP-007.
///
/// Carries the category's name beside its id because the categoriser
/// compares categories by name in one place — the merchant's — and a
/// second query to learn the name of an id it already holds would be a
/// query per item.
class KeywordMatch extends Equatable {
  /// Creates a match.
  const KeywordMatch({
    required this.keyword,
    required this.categoryId,
    required this.categoryName,
    required this.matchType,
    this.priority = 5,
    this.isUserDefined = false,
  });

  /// The keyword, lower case as stored.
  final String keyword;

  /// The category the keyword maps to.
  final int categoryId;

  /// That category's display name.
  final String categoryName;

  /// How [keyword] was compared.
  final KeywordMatchType matchType;

  /// 1–10; the seed's entries are 5 and the user's corrections are 10.
  final int priority;

  /// True when the user taught this mapping (FR-RCP-015) rather than the
  /// seed shipping it.
  final bool isUserDefined;

  @override
  List<Object?> get props => [
    keyword,
    categoryId,
    categoryName,
    matchType,
    priority,
    isUserDefined,
  ];
}
