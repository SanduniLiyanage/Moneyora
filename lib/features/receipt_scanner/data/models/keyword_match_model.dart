import '../../domain/entities/keyword_match.dart';

/// Persistence mapping for [KeywordMatch]. FR-RCP-007.
///
/// The stored strings for [KeywordMatchType] live here, not on the enum:
/// what the schema calls them is the data layer's business. They are the
/// `match_type` check constraint's own values — `startswith`, one word,
/// lower case, as `v1_initial.dart` and `v3_receipt_scanner.dart` wrote it.
class KeywordMatchModel extends KeywordMatch {
  /// Creates a model directly. Prefer [fromMap].
  const KeywordMatchModel({
    required super.keyword,
    required super.categoryId,
    required super.categoryName,
    required super.matchType,
    super.priority,
    super.isUserDefined,
  });

  /// Rebuilds a model from a `keyword_dictionary` row joined to
  /// `categories` for its `category_name`.
  factory KeywordMatchModel.fromMap(Map<String, Object?> map) =>
      KeywordMatchModel(
        keyword: map['keyword']! as String,
        categoryId: map['category_id']! as int,
        categoryName: map['category_name']! as String,
        matchType: decodeMatchType(map['match_type']! as String),
        priority: map['priority']! as int,
        isUserDefined: map['is_user_defined'] == 1,
      );

  /// The schema's string for [type].
  static String encodeMatchType(KeywordMatchType type) => switch (type) {
    KeywordMatchType.exact => 'exact',
    KeywordMatchType.contains => 'contains',
    KeywordMatchType.startsWith => 'startswith',
  };

  /// The enum for the schema's [value].
  static KeywordMatchType decodeMatchType(String value) => switch (value) {
    'exact' => KeywordMatchType.exact,
    'contains' => KeywordMatchType.contains,
    'startswith' => KeywordMatchType.startsWith,
    _ => throw ArgumentError.value(value, 'value', 'Unknown match_type'),
  };
}
