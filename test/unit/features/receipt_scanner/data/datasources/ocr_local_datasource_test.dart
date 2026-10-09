import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/ocr_local_datasource.dart';

/// The datasource against a fake recogniser.
///
/// Nothing here reaches ML Kit. What is being tested is the part that can be
/// got wrong silently: whether two blocks — names down the left, prices down
/// the right — come out as one line per row, and whether a recogniser that
/// finds nothing or throws becomes something the repository above knows how
/// to convert. The recogniser itself is proved on a device, with a photo.
class _FakeRecogniser implements TextRecogniser {
  _FakeRecogniser(this.result);

  final mlkit.RecognizedText result;
  Exception? throwWith;
  mlkit.InputImage? seen;

  @override
  Future<mlkit.RecognizedText> processImage(mlkit.InputImage image) async {
    seen = image;
    if (throwWith case final e?) throw e;
    return result;
  }

  @override
  Future<void> close() async {}
}

/// One recognised line at a position, as ML Kit would report it.
mlkit.TextLine line(
  String text, {
  required double left,
  required double top,
  double width = 120,
  double height = 20,
}) => mlkit.TextLine(
  text: text,
  elements: const [],
  boundingBox: Rect.fromLTWH(left, top, width, height),
  recognizedLanguages: const [],
  cornerPoints: const [],
  confidence: null,
  angle: null,
);

/// A line printed on a receipt photographed at a tilt: its top edge drops
/// [slope] pixels for every pixel to the right, and so does the page under
/// it, measured from x = 0. The corner points are the turned line's, and
/// the box is the upright box around them, as ML Kit reports both.
mlkit.TextLine tilted(
  String text, {
  required double left,
  required double top,
  required double slope,
  double width = 120,
  double height = 20,
}) {
  final angle = atan(slope);
  Point<int> at(double along, double down) => Point(
    (left + along * cos(angle) - down * sin(angle)).round(),
    (top + left * slope + along * sin(angle) + down * cos(angle)).round(),
  );
  final corners = [at(0, 0), at(width, 0), at(width, height), at(0, height)];
  final xs = corners.map((p) => p.x.toDouble());
  final ys = corners.map((p) => p.y.toDouble());
  return mlkit.TextLine(
    text: text,
    elements: const [],
    boundingBox: Rect.fromLTRB(
      xs.reduce(min),
      ys.reduce(min),
      xs.reduce(max),
      ys.reduce(max),
    ),
    recognizedLanguages: const [],
    cornerPoints: corners,
    confidence: null,
    angle: null,
  );
}

/// A block around [lines], with the box ML Kit would draw around them.
mlkit.TextBlock block(List<mlkit.TextLine> lines) => mlkit.TextBlock(
  text: lines.map((l) => l.text).join('\n'),
  lines: lines,
  boundingBox: lines
      .map((l) => l.boundingBox)
      .reduce((a, b) => a.expandToInclude(b)),
  recognizedLanguages: const [],
  cornerPoints: const [],
);

mlkit.RecognizedText read(List<mlkit.TextBlock> blocks) => mlkit.RecognizedText(
  text: blocks.map((b) => b.text).join('\n'),
  blocks: blocks,
);

void main() {
  group('reading order', () {
    const order = OcrLocalDataSourceImpl.linesInReadingOrder;

    test('a names column and a prices column become one line per row', () {
      // The case the whole mapping exists for: flattened block by block,
      // this would read every name and then every price, and the parser
      // would find no items.
      final names = block([
        line('RICE 5KG', left: 10, top: 100),
        line('BREAD', left: 10, top: 130),
        line('SHAMPOO 200ML', left: 10, top: 160),
      ]);
      final prices = block([
        line('1,250.00', left: 300, top: 100),
        line('180.00', left: 300, top: 130),
        line('650.00', left: 300, top: 160),
      ]);

      expect(order(read([prices, names])), [
        'RICE 5KG 1,250.00',
        'BREAD 180.00',
        'SHAMPOO 200ML 650.00',
      ]);
    });

    test('rows come out top to bottom whatever order the blocks arrived', () {
      final footer = block([line('TOTAL 2,080.00', left: 10, top: 300)]);
      final header = block([
        line('KEELLS SUPER', left: 10, top: 20),
        line('COLOMBO 03', left: 10, top: 50),
      ]);
      final body = block([line('RICE 5KG 1,250.00', left: 10, top: 100)]);

      expect(order(read([footer, body, header])), [
        'KEELLS SUPER',
        'COLOMBO 03',
        'RICE 5KG 1,250.00',
        'TOTAL 2,080.00',
      ]);
    });

    test('a slightly tilted row still joins', () {
      // A phone photo is never quite square. The price sits a few pixels
      // below the name and still overlaps it by more than half a line.
      final names = block([line('MILK 1L', left: 10, top: 100)]);
      final prices = block([line('240.00', left: 300, top: 108)]);

      expect(order(read([names, prices])), ['MILK 1L 240.00']);
    });

    test('adjacent rows do not merge', () {
      // Lines one line-height apart share no vertical extent, and a row
      // must not swallow the row beneath it.
      final names = block([
        line('MILK 1L', left: 10, top: 100),
        line('BREAD', left: 10, top: 120),
      ]);
      final prices = block([
        line('240.00', left: 300, top: 100),
        line('180.00', left: 300, top: 120),
      ]);

      expect(order(read([names, prices])), ['MILK 1L 240.00', 'BREAD 180.00']);
    });

    test('a row is measured from its first line, not its running extent', () {
      // Three lines each overlapping the previous by half but drifting down
      // the page: with a growing extent the third would join the first's
      // row; against the anchor it does not.
      final drift = block([
        line('A', left: 10, top: 100),
        line('B', left: 150, top: 110),
        line('C', left: 300, top: 121),
      ]);

      expect(order(read([drift])), ['A B', 'C']);
    });

    test('a three-column row reads left to right', () {
      final qty = block([line('2 x', left: 10, top: 100)]);
      final name = block([line('CHICKEN KOTTU', left: 60, top: 100)]);
      final price = block([line('1,700.00', left: 300, top: 100)]);

      expect(order(read([price, qty, name])), ['2 x CHICKEN KOTTU 1,700.00']);
    });

    test('a two-line item stays two lines for the parser to join', () {
      // The parser owns the vertical join (a name over a quantity line);
      // the datasource must not pre-empt it with a guess.
      final body = block([
        line('MILK 1L', left: 10, top: 100),
        line('2 x 240.00', left: 40, top: 125),
        line('480.00', left: 300, top: 125),
      ]);

      expect(order(read([body])), ['MILK 1L', '2 x 240.00 480.00']);
    });

    test('nothing read is no lines', () {
      expect(order(read(const [])), isEmpty);
    });
  });

  group('a camera photo, taken at a tilt. FR-RCP-003', () {
    const order = OcrLocalDataSourceImpl.linesInReadingOrder;

    // Rows 30 pixels apart, prices 600 pixels right of their names. At a
    // slope of 0.05 (under three degrees) a price drops 30 pixels: a whole
    // row, level with the next row's name.
    List<mlkit.TextBlock> receipt(double slope) => [
      block([
        tilted('RICE 5KG', left: 10, top: 100, slope: slope),
        tilted('BREAD', left: 10, top: 130, slope: slope),
        tilted('SHAMPOO 200ML', left: 10, top: 160, slope: slope),
        tilted('TOTAL', left: 10, top: 190, slope: slope),
      ]),
      block([
        tilted('1,250.00', left: 610, top: 100, slope: slope),
        tilted('180.00', left: 610, top: 130, slope: slope),
        tilted('650.00', left: 610, top: 160, slope: slope),
        tilted('2,080.00', left: 610, top: 190, slope: slope),
      ]),
    ];

    const rows = [
      'RICE 5KG 1,250.00',
      'BREAD 180.00',
      'SHAMPOO 200ML 650.00',
      'TOTAL 2,080.00',
    ];

    test('each price stays with its own name, tilted down', () {
      expect(order(read(receipt(0.05))), rows);
    });

    test('and tilted up', () {
      expect(order(read(receipt(-0.05))), rows);
    });

    test('square, as a screenshot is, nothing changes', () {
      expect(order(read(receipt(0))), rows);
    });

    test('the tilt is the median of the long lines', () {
      final lines = [
        for (final b in receipt(0.05)) ...b.lines,
        // One stamp at a steep angle does not turn the page.
        tilted('PAID', left: 300, top: 400, slope: 0.6, width: 90),
      ];

      expect(OcrLocalDataSourceImpl.pageTilt(lines), closeTo(atan(0.05), 0.01));
    });

    test('lines without corner points are read upright', () {
      expect(OcrLocalDataSourceImpl.pageTilt([line('A', left: 0, top: 0)]), 0);
    });
  });

  group('recognising a file', () {
    test('opens the path as a file image and returns the lines', () async {
      final recogniser = _FakeRecogniser(
        read([
          block([line('KEELLS SUPER', left: 10, top: 20)]),
        ]),
      );
      final source = OcrLocalDataSourceImpl(recogniser);

      final text = await source.recognise('/cache/receipt.jpg');

      expect(text.lines, ['KEELLS SUPER']);
      expect(recogniser.seen?.filePath, '/cache/receipt.jpg');
      expect(recogniser.seen?.type, mlkit.InputImageType.file);
    });

    test('an image with no text is an OcrException', () async {
      // Not an empty RecognisedText: the parser would turn that into the
      // same failure one stage later, but with a message about the parse
      // rather than the photo.
      final source = OcrLocalDataSourceImpl(_FakeRecogniser(read(const [])));

      await expectLater(
        source.recognise('/cache/blank.jpg'),
        throwsA(
          isA<OcrException>().having(
            (e) => e.message,
            'message',
            contains('No text'),
          ),
        ),
      );
    });

    test('whitespace only is no text', () async {
      final source = OcrLocalDataSourceImpl(
        _FakeRecogniser(
          read([
            block([line('   ', left: 10, top: 20)]),
          ]),
        ),
      );

      await expectLater(
        source.recognise('/cache/blank.jpg'),
        throwsA(isA<OcrException>()),
      );
    });

    test('a recogniser failure does not escape as itself', () async {
      // A missing file or an unreadable format surfaces from the channel as
      // a PlatformException. Nothing above data/ has a try/catch, so it has
      // to become an AppException here, with its cause kept.
      final recogniser = _FakeRecogniser(read(const []))
        ..throwWith = const _ChannelLikeException();
      final source = OcrLocalDataSourceImpl(recogniser);

      await expectLater(
        source.recognise('/cache/missing.jpg'),
        throwsA(
          isA<OcrException>().having(
            (e) => e.cause,
            'cause',
            isA<_ChannelLikeException>(),
          ),
        ),
      );
    });
  });
}

/// Stands in for a platform-channel error.
class _ChannelLikeException implements Exception {
  const _ChannelLikeException();
}
