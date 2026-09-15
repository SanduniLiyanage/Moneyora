/// The on-device recogniser, and the one piece of judgement between it and
/// the parser: which of ML Kit's lines sit on the same printed row.
///
/// Everything here throws [AppException] on failure, per the layer contract
/// in `docs/ARCHITECTURE.md` §3; `ReceiptRepositoryImpl` converts.
library;

import 'dart:math';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/recognised_text.dart';

/// The slice of ML Kit's `TextRecognizer` this datasource uses.
///
/// An interface for the same reason [LlmApiKeyStore] is one: the real
/// implementation talks to the native recogniser over a platform channel
/// that cannot run in a unit test. [MlKitTextRecogniser] is the one that
/// ships; a test hands in a fake that returns a `RecognizedText` it built.
abstract class TextRecogniser {
  /// Runs recognition over [image] and returns every block found.
  Future<mlkit.RecognizedText> processImage(mlkit.InputImage image);

  /// Releases the native recogniser.
  Future<void> close();
}

/// Reads the text off a receipt image. FR-RCP-004.
abstract class OcrLocalDataSource {
  /// The lines printed on the image at [imagePath], top to bottom, with the
  /// pieces of one row joined into one line.
  ///
  /// Throws [OcrException] when the image could not be read or nothing
  /// legible was found on it.
  Future<RecognisedText> recognise(String imagePath);
}

/// Fulfils [OcrLocalDataSource] over a [TextRecogniser].
///
/// ## Why the rows are reassembled here
///
/// ML Kit groups lines into blocks by proximity, and a receipt is two
/// columns: names down the left, prices down the right. On a clean print it
/// often returns one block per column, so flattening block by block would
/// list every name and then every price — and `ParseReceiptText`, which
/// reads a price as the figure ending a line, would find no items at all.
/// The parser takes line order as printed order on purpose (it is pure
/// text and has no geometry to work with), so the geometry is settled here:
/// every line is placed by its bounding box, lines that overlap vertically
/// are one row, and a row reads left to right.
class OcrLocalDataSourceImpl implements OcrLocalDataSource {
  /// Creates a datasource over [recogniser].
  const OcrLocalDataSourceImpl(this._recogniser);

  final TextRecogniser _recogniser;

  @override
  Future<RecognisedText> recognise(String imagePath) async {
    final mlkit.RecognizedText read;
    try {
      read = await _recogniser.processImage(
        mlkit.InputImage.fromFilePath(imagePath),
      );
    } on Exception catch (e) {
      // A missing file, an unreadable format, a native failure: the platform
      // exception's own message names an SDK class, not anything the reader
      // can act on.
      throw OcrException('Could not read that image.', cause: e);
    }

    final text = RecognisedText(linesInReadingOrder(read));
    if (text.isBlank) {
      throw const OcrException('No text was found on that image.');
    }
    return text;
  }

  /// Every line in [read], top to bottom, with the lines of one printed row
  /// joined left to right by a single space.
  ///
  /// Two lines share a row when their boxes overlap vertically by at least
  /// half the shorter one's height — enough to keep a name beside its price
  /// on a slightly tilted photo, and not enough to let a tall line swallow
  /// its neighbours above and below. Each row is compared through its first
  /// line rather than its running extent so a row cannot creep down a
  /// skewed receipt one line at a time.
  ///
  /// Static so the rule can be tested without a recogniser.
  static List<String> linesInReadingOrder(mlkit.RecognizedText read) {
    final lines = [for (final block in read.blocks) ...block.lines]
      ..sort(
        (a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy),
      );

    final rows = <List<mlkit.TextLine>>[];
    for (final line in lines) {
      final row = rows.where((r) => _sameRow(r.first, line)).firstOrNull;
      if (row == null) {
        rows.add([line]);
      } else {
        row.add(line);
      }
    }

    return [
      for (final row in rows)
        (row..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left)))
            .map((l) => l.text)
            .join(' '),
    ];
  }

  static bool _sameRow(mlkit.TextLine a, mlkit.TextLine b) {
    final overlap =
        min(a.boundingBox.bottom, b.boundingBox.bottom) -
        max(a.boundingBox.top, b.boundingBox.top);
    final shorter = min(a.boundingBox.height, b.boundingBox.height);
    return shorter > 0 && overlap >= shorter / 2;
  }
}
