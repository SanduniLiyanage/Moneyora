import 'package:equatable/equatable.dart';

/// What OCR read off a receipt image, as lines of text. FR-RCP-004.
///
/// The boundary between the recogniser and the parser: ML Kit produces
/// blocks of lines, this keeps the lines in reading order and forgets the
/// geometry, and [ParseReceiptText] never sees an image. A test can build
/// one from a string; the ML Kit datasource builds one from a
/// `RecognizedText`.
class RecognisedText extends Equatable {
  /// Creates the text from its lines, as read.
  const RecognisedText(this.lines);

  /// Splits [text] on line breaks. Blank lines are kept — the parser drops
  /// them — so a line's index still points at the source.
  RecognisedText.fromString(String text) : lines = text.split('\n');

  /// One entry per printed line, top to bottom, untrimmed.
  final List<String> lines;

  /// True when nothing but whitespace was read.
  bool get isBlank => lines.every((l) => l.trim().isEmpty);

  @override
  List<Object?> get props => [lines];
}
