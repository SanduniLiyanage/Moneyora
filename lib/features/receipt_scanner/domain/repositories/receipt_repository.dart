import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/recognised_text.dart';

/// The scanner's boundary with the device: the recogniser behind it, and
/// in later slices the scan records. FR-RCP-004.
///
/// SDD §9.1 gives this interface three methods. `confirmScan` arrives with
/// FR-RCP-009, when there is a `receipt_scans` row to write and per-item
/// transactions to create under it; `getScanHistory` with FR-RCP-013's
/// history view. Declaring them now would put two methods on `main` that
/// nothing could implement, so each lands with the slice that can.
///
/// The SDD's `File imageFile` is a path here. The domain then stays free
/// of `dart:io`, and a path is what both ends of the pipeline already deal
/// in: `image_picker` hands back an `XFile.path`, and ML Kit opens an
/// `InputImage.fromFilePath`.
abstract class ReceiptRepository {
  /// Every line of text the on-device recogniser read off the image at
  /// [imagePath], in printed order.
  ///
  /// An [OcrFailure] when nothing legible was found or the image could not
  /// be read — FR-RCP-011's low-confidence path starts here.
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath);
}
