import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/parsed_receipt.dart';
import '../entities/recognised_text.dart';
import '../entities/scanned_receipt.dart';
import 'categorise_receipt.dart';
import 'parse_receipt_text.dart';
import 'scan_receipt.dart';

/// A receipt photo to what the review screen opens with: recognised,
/// parsed, and categorised. FR-RCP-004, FR-RCP-005, FR-RCP-007.
///
/// Stages three to five of the pipeline (SDD §7.2), run in order, the
/// first failure returned as it is: [ScanReceipt]'s `OcrFailure` for an
/// unreadable photo, [ParseReceiptText]'s for text with no items and no
/// total, [CategoriseReceipt]'s for a dictionary that could not be read.
/// Each stage keeps its own tests; this one proves only the sequencing
/// and that the path travels through to the result, which is what the
/// expenses will link to (FR-RCP-009).
///
/// FR-RCP-003's preprocessing belongs between the picker and the first
/// stage here, once it exists; the path in is the path the recogniser
/// opens until then.
class ReadReceiptImage implements UseCase<ScannedReceipt, String> {
  /// Creates the use case over the three stages.
  const ReadReceiptImage(this._scan, this._parse, this._categorise);

  final ScanReceipt _scan;
  final ParseReceiptText _parse;
  final CategoriseReceipt _categorise;

  @override
  Future<Either<Failure, ScannedReceipt>> call(String params) async {
    final RecognisedText text;
    switch (await _scan(params)) {
      case Left(value: final failure):
        return Left(failure);
      case Right(value: final read):
        text = read;
    }

    final ParsedReceipt parsed;
    switch (await _parse(text)) {
      case Left(value: final failure):
        return Left(failure);
      case Right(value: final found):
        parsed = found;
    }

    final categorised = await _categorise(parsed);
    return categorised.map(
      (receipt) => ScannedReceipt(imagePath: params, receipt: receipt),
    );
  }
}
