import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/receipt_image_source.dart';
import '../entities/receipt_scan.dart';
import '../entities/recognised_text.dart';

/// The scanner's boundary with the device and the database: the
/// recogniser behind [scanReceipt], the scan records behind the rest.
/// FR-RCP-004, FR-RCP-009, FR-RCP-013.
///
/// SDD §9.1's three methods, plus the picker the SDD leaves to the screen.
///
/// The SDD's `File imageFile` is a path here. The domain then stays free
/// of `dart:io`, and a path is what both ends of the pipeline already deal
/// in: `image_picker` hands back an `XFile.path`, and ML Kit opens an
/// `InputImage.fromFilePath`.
abstract class ReceiptRepository {
  /// Asks the device for a receipt photo from [source] and returns its
  /// path, or null when the user backed out without choosing one.
  /// FR-RCP-002.
  ///
  /// A [PermissionFailure] when the camera or the photo library was
  /// refused; the screen says which and leaves the setting to the user.
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source);

  /// Every line of text the on-device recogniser read off the image at
  /// [imagePath], in printed order.
  ///
  /// An [OcrFailure] when nothing legible was found or the image could not
  /// be read — FR-RCP-011's low-confidence path starts here.
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath);

  /// Saves [scan] and its items as one record, returning the scan's id.
  /// FR-RCP-009.
  ///
  /// The record only — the expenses it links go through `ExpenseWriter`,
  /// the transactions feature's own write path, and [ConfirmReceipt] is
  /// where the two are sequenced. Written with whatever [scan.status]
  /// says; the confirm step passes `confirmed`.
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan);

  /// Every scan record with its items, newest first. FR-RCP-013.
  ///
  /// All of them, unfiltered: the history is searchable, but the search
  /// is the use case's ([GetScanHistory]) so its rules are pure Dart and
  /// a match on an item name needs no join. A `Future` rather than a
  /// stream, as the SDD has it — nothing writes a scan while the history
  /// is on screen, and the screen re-reads on open.
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory();
}
