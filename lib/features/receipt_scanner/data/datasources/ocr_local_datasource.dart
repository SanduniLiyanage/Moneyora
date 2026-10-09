/// The on-device recogniser, and the one piece of judgement between it and
/// the parser: which of ML Kit's lines sit on the same printed row.
///
/// Everything here throws [AppException] on failure, per the layer contract
/// in `docs/ARCHITECTURE.md` §3; `ReceiptRepositoryImpl` converts.
library;

import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
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
    assert(() {
      // Debug builds only: the rows as the parser will see them, so a
      // receipt the parser misread can be turned into a fixture from the
      // console rather than guessed at from the photo. Nothing in release.
      debugPrint('[receipt-ocr] ${text.lines.length} rows from $imagePath');
      for (final line in text.lines) {
        debugPrint('[receipt-ocr] | $line');
      }
      return true;
    }());
    if (text.isBlank) {
      throw const OcrException('No text was found on that image.');
    }
    return text;
  }

  /// Every line in [read], top to bottom, with the lines of one printed row
  /// joined left to right by a single space.
  ///
  /// Two lines share a row when their boxes overlap vertically by at least
  /// half the shorter one's height — enough to keep a name beside its price,
  /// and not enough to let a tall line swallow its neighbours above and
  /// below. Each row is compared through its first line rather than its
  /// running extent so a row cannot creep down the receipt one line at a
  /// time.
  ///
  /// **Measured across the page's tilt, not the photo's.** A camera photo
  /// is never square to the receipt: tilted by three degrees, a price 600
  /// pixels to the right of its name sits 30 pixels lower — more than a
  /// line — and level with the *next* row's name. Compared upright, names
  /// and prices paired off one row out, or not at all, which is what made
  /// camera photos misread and screenshots not. So the page's tilt is
  /// taken from the lines themselves (each line's top edge, from ML Kit's
  /// corner points; the median of the long ones), and every line is placed
  /// and measured in the turned frame. A line with no corner points — and a
  /// screenshot, which is square — is placed exactly as before.
  ///
  /// Static so the rule can be tested without a recogniser.
  static List<String> linesInReadingOrder(mlkit.RecognizedText read) {
    final lines = [for (final block in read.blocks) ...block.lines];
    final tilt = pageTilt(lines);
    final placed = [for (final line in lines) _Placed(line, tilt)]
      ..sort((a, b) => a.across.compareTo(b.across));

    final rows = <List<_Placed>>[];
    for (final line in placed) {
      final row = rows.where((r) => r.first.sharesRowWith(line)).firstOrNull;
      if (row == null) {
        rows.add([line]);
      } else {
        row.add(line);
      }
    }

    return [
      for (final row in rows)
        (row..sort((a, b) => a.along.compareTo(b.along)))
            .map((p) => p.line.text)
            .join(' '),
    ];
  }

  /// The page's tilt, in radians, clockwise positive: the median slope of
  /// the top edges of the lines long enough to give one, and 0 when none
  /// does. More than 20 degrees is not a tilt this can correct — a photo
  /// that far round is read as it stands.
  ///
  /// Median rather than mean: a single stamp or a handwritten note at an
  /// angle must not turn the whole page.
  static double pageTilt(List<mlkit.TextLine> lines) {
    final slopes = <double>[];
    for (final line in lines) {
      final corners = line.cornerPoints;
      if (corners.length < 4) continue;
      final dx = (corners[1].x - corners[0].x).toDouble();
      final dy = (corners[1].y - corners[0].y).toDouble();
      final height = _distance(corners[0], corners[3]);
      // Short lines — a "1", a "x" — give an angle that is mostly noise.
      if (dx <= 0 || dx < height * 2) continue;
      slopes.add(atan2(dy, dx));
    }
    if (slopes.isEmpty) return 0;
    slopes.sort();
    final middle = slopes.length ~/ 2;
    final median = slopes.length.isOdd
        ? slopes[middle]
        : (slopes[middle - 1] + slopes[middle]) / 2;
    return median.abs() > _maxTilt ? 0 : median;
  }

  static const double _maxTilt = 20 * pi / 180;

  static double _distance(Point<int> a, Point<int> b) =>
      sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2));
}

/// A line placed in the page's own frame: turned back by the page's tilt,
/// so "across" is down the receipt and "along" is along its print.
class _Placed {
  factory _Placed(mlkit.TextLine line, double tilt) {
    final centre = line.boundingBox.center;
    final c = cos(tilt);
    final s = sin(tilt);
    final corners = line.cornerPoints;
    // The line's own height, when its corners give it; its box's otherwise,
    // which is the same thing for a square photo.
    final height = corners.length >= 4 && tilt != 0
        ? OcrLocalDataSourceImpl._distance(corners[0], corners[3])
        : line.boundingBox.height;
    return _Placed._(
      line,
      across: -s * centre.dx + c * centre.dy,
      along: c * centre.dx + s * centre.dy,
      height: height,
    );
  }

  const _Placed._(
    this.line, {
    required this.across,
    required this.along,
    required this.height,
  });

  final mlkit.TextLine line;

  /// How far down the receipt its middle is.
  final double across;

  /// How far along the printed row its middle is.
  final double along;

  final double height;

  /// True when the two overlap, down the receipt, by at least half the
  /// shorter one's height.
  bool sharesRowWith(_Placed other) {
    final overlap =
        min(across + height / 2, other.across + other.height / 2) -
        max(across - height / 2, other.across - other.height / 2);
    final shorter = min(height, other.height);
    return shorter > 0 && overlap >= shorter / 2;
  }
}
