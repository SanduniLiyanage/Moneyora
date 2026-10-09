import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/parsed_receipt.dart';
import '../entities/recognised_text.dart';
import 'parsing/receipt_body_reader.dart';
import 'parsing/receipt_header_reader.dart';
import 'parsing/receipt_profile.dart';
import 'parsing/receipt_reconciler.dart';
import 'parsing/receipt_vocabulary.dart';

/// Merchant, date, line items, total, tax, receipt number and how it was
/// paid, from the lines OCR read. FR-RCP-005, FR-RCP-006, FR-RCP-011,
/// E-31, E-45.
///
/// The fourth stage of the pipeline (SDD §7.2): after ML Kit, before the
/// categoriser. Pure text — nothing here knows an image existed, which is
/// what lets a test state a receipt as a string.
///
/// Three stages of its own, each in `parsing/` and each testable on plain
/// text:
/// 1. [ReceiptHeaderReader] — the phone's and the email's text around the
///    receipt set aside, then the merchant, the date and time, and the
///    receipt number;
/// 2. [ReceiptBodyReader] — every other priced line sorted into items,
///    discounts, and summary lines (totals, tax, payments, change);
/// 3. [ReceiptReconciler] — discounts matched to their items, tax spread,
///    and the result checked against the total, trying other readings
///    before giving up on one that does not add up.
///
/// The words each stage looks for are a [ReceiptVocabulary]; a
/// [ReceiptProfile] that recognises the receipt adds a shop's own.
///
/// Nothing here is a claim about accuracy. The real receipts among the
/// fixtures in the test are the only basis for one, and every one so far
/// has broken a rule. ML Kit's line order is taken as printed order.
class ParseReceiptText implements UseCase<ParsedReceipt, RecognisedText> {
  /// Creates the parser. Stateless.
  const ParseReceiptText();

  /// The shops with a profile.
  static const List<ReceiptProfile> knownProfiles = [KeellsProfile()];

  @override
  Future<Either<Failure, ParsedReceipt>> call(RecognisedText params) async {
    final receipt = parse(params);
    if (receipt.items.isEmpty && receipt.totalCents == null) {
      return const Left(OcrFailure());
    }
    return Right(receipt);
  }

  /// Parses [text], returning whatever was found — possibly nothing.
  ///
  /// Static so a test can state the rules without the failure wrapper.
  /// [localOffset] is the device's offset from UTC, for a date only an
  /// email header gives; the clock's own when null.
  static ParsedReceipt parse(
    RecognisedText text, {
    List<ReceiptProfile> profiles = knownProfiles,
    Duration? localOffset,
  }) {
    final lines = text.lines;
    var vocabulary = ReceiptVocabulary.standard;
    for (final profile in profiles) {
      if (profile.recognises(lines)) {
        vocabulary = vocabulary.extendedBy(profile.vocabulary);
      }
    }

    final header = ReceiptHeaderReader(
      vocabulary,
      localOffset: localOffset,
    ).read(lines);
    final body = ReceiptBodyReader(vocabulary)
        .read(lines, skip: header.consumed);
    final result = ReceiptReconciler.reconcile(body);

    return ParsedReceipt(
      merchantName: header.merchantName,
      receiptDate: header.receiptDate,
      items: result.items,
      totalCents: result.totalCents,
      taxCents: result.taxCents,
      receiptNumber: header.receiptNumber,
      paymentMethod: body.paymentMethod,
      guessedFields: {
        if (header.merchantGuessed) ReceiptField.merchant,
        if (header.dateGuessed) ReceiptField.date,
        if (result.totalGuessed) ReceiptField.total,
      },
    );
  }
}
