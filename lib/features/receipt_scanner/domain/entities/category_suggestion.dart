import 'package:equatable/equatable.dart';

/// Which of FR-RCP-007's layers decided a suggestion.
enum SuggestionSource {
  /// Layer 1: a seed keyword matched the item.
  keyword,

  /// Layer 2: a keyword the user taught matched the item.
  userHistory,

  /// Layer 3 alone: nothing matched the item, and the merchant's category
  /// is the only lead.
  merchant,

  /// Nothing matched; the user picks.
  none,
}

/// A category for one receipt item, with how sure the categoriser is.
/// FR-RCP-007.
class CategorySuggestion extends Equatable {
  /// Creates a suggestion.
  const CategorySuggestion({
    required this.confidence,
    required this.source,
    this.categoryId,
    this.categoryName,
  }) : assert(confidence >= 0 && confidence <= 100);

  /// No category, no confidence.
  static const none = CategorySuggestion(
    confidence: 0,
    source: SuggestionSource.none,
  );

  /// The suggested category, null when [source] is [SuggestionSource.none].
  final int? categoryId;

  /// Its display name.
  final String? categoryName;

  /// 0–100, the SRS's scale.
  final int confidence;

  /// Which layer decided.
  final SuggestionSource source;

  @override
  List<Object?> get props => [categoryId, categoryName, confidence, source];
}
