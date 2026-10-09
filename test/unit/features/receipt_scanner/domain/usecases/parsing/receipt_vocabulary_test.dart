import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_vocabulary.dart';

void main() {
  final vocabulary = ReceiptVocabulary.standard;

  group('mend', () {
    test('reads a label word through the characters OCR confuses', () {
      expect(vocabulary.mend('Net Totai'), 'Net total');
      expect(vocabulary.mend('NET T0TAL'), 'NET total');
      expect(vocabulary.mend('TOTA1'), 'total');
      expect(vocabulary.mend('CA5H'), 'cash');
      expect(vocabulary.mend('8alance'), 'balance');
    });

    test('reads total and time through one more edit', () {
      expect(vocabulary.mend('Net Tota'), 'Net total');
      expect(vocabulary.mend('Sub fotal'), 'Sub total');
      expect(vocabulary.mend('ime End: 14:31:32'), 'time End: 14:31:32');
    });

    test('leaves real words and figures alone', () {
      expect(vocabulary.mend('LIP GLOSS'), 'LIP GLOSS');
      expect(vocabulary.mend('SERVICE CHARGE'), 'SERVICE CHARGE');
      expect(vocabulary.mend('CARE PACK 1000 50.00'), 'CARE PACK 1000 50.00');
      expect(vocabulary.mend('SCE0833'), 'SCE0833');
    });

    test('so a misread label keeps its role', () {
      expect(vocabulary.roleOf('Net Totai'), LineRole.net);
      expect(vocabulary.roleOf('Sub fotal'), LineRole.gross);
      expect(vocabulary.roleOf('CA5H'), LineRole.tender);
      expect(vocabulary.roleOf('LIP GLOSS'), isNull);
    });
  });

  group('column titles', () {
    test('three titles and a word a cropped photo cut short', () {
      expect(ReceiptVocabulary.isColumnTitles('TEM QTY PRICE AMOUNT'), isTrue);
      expect(
        ReceiptVocabulary.isColumnTitles('# Item Description Oty'),
        isTrue,
      );
    });

    test('never a priced line, nor a line with two strangers', () {
      expect(
        ReceiptVocabulary.isColumnTitles('ITEM TOTAL VALUE 535.00'),
        isFalse,
      );
      expect(ReceiptVocabulary.isColumnTitles('MY QTY PRICE BAG'), isFalse);
    });
  });

  group('the loyalty marker', () {
    test('knows the words that open a points block', () {
      for (final line in [
        'Loyalty Customer',
        'Star Points',
        'Earned on this bill: .60',
        'REWARDS',
      ]) {
        expect(vocabulary.loyaltyMarker.hasMatch(line), isTrue, reason: line);
      }
      expect(vocabulary.loyaltyMarker.hasMatch('POINTED GOURD'), isFalse);
    });
  });
}
