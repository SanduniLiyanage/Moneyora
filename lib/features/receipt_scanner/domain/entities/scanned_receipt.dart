import 'package:equatable/equatable.dart';

import 'categorised_receipt.dart';

/// A receipt photo and everything the pipeline read off it. FR-RCP-008.
///
/// What the capture screen hands the review screen: the path the expenses
/// will link to (FR-RCP-009, FR-RCP-012) beside the parse and its
/// suggestions. [CategorisedReceipt] cannot carry the path itself — the
/// categoriser never sees an image — and a screen given one without the
/// other could show a review it could not post.
class ScannedReceipt extends Equatable {
  /// Creates the pair.
  const ScannedReceipt({required this.imagePath, required this.receipt});

  /// Where the photo lives on disk.
  final String imagePath;

  /// What was read and suggested.
  final CategorisedReceipt receipt;

  @override
  List<Object?> get props => [imagePath, receipt];
}
