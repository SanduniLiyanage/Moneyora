import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/receipt_scan.dart';
import '../repositories/receipt_repository.dart';

/// What the history screen asks for: every scan, or those matching a
/// search. FR-RCP-013.
class ReceiptHistoryQuery extends Equatable {
  /// Creates a query. An empty or blank [search] asks for everything.
  const ReceiptHistoryQuery({this.search = ''});

  /// The words typed into the search field.
  final String search;

  @override
  List<Object?> get props => [search];
}

/// The receipts scanned so far, newest first, narrowed by a search.
/// FR-RCP-013.
///
/// The SRS asks for a "searchable" history and stops there, so the rule
/// is stated here and nowhere else: **every word typed must appear
/// somewhere on the receipt** — its merchant, its printed number or one
/// of its item names — case-insensitively, as a substring. Words rather
/// than the phrase, so "keells rice" finds the Keells receipt with rice
/// on it; substrings rather than whole words, so "pana" finds PANADOL.
/// Across fields rather than within one, so "keells 4521" finds the
/// receipt by store and number together.
///
/// Nothing is matched on the total or the date: a number typed is far
/// more likely a receipt number, and the list shows both figures so the
/// eye can do what a text box cannot do well.
///
/// Filtering happens here rather than in SQL because the item names live
/// in a second table, the receipts number in the tens, and a rule in
/// Dart has a test that says exactly what it does.
class GetScanHistory
    implements UseCase<List<ReceiptScan>, ReceiptHistoryQuery> {
  /// Creates the use case.
  const GetScanHistory(this._repository);

  final ReceiptRepository _repository;

  @override
  Future<Either<Failure, List<ReceiptScan>>> call(
    ReceiptHistoryQuery params,
  ) async {
    final terms = termsOf(params.search);
    final history = await _repository.getScanHistory();
    if (terms.isEmpty) return history;
    return history.map(
      (scans) => [
        for (final scan in scans)
          if (matches(scan, terms)) scan,
      ],
    );
  }

  /// The words in [search], lower-cased; none for a blank search.
  static List<String> termsOf(String search) => [
    for (final word in search.toLowerCase().split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
  ];

  /// True when every one of [terms] appears on [scan] somewhere.
  static bool matches(ReceiptScan scan, List<String> terms) {
    final haystack = [
      if (scan.merchantName case final m?) m.toLowerCase(),
      if (scan.receiptNumber case final n?) n.toLowerCase(),
      for (final item in scan.items) item.item.name.toLowerCase(),
    ];
    return terms.every((term) => haystack.any((text) => text.contains(term)));
  }
}
