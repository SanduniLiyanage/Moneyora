import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/priced_line.dart';

void main() {
  group('the figure ending the line', () {
    test('S for 5, as on a camera photo', () {
      expect(PricedLine.of('S99.60')!.cents, 59960);
      expect(PricedLine.of('S99.60')!.isWordless, isTrue);
    });
  });

  group('a code row', () {
    test('is an article code and its figures, with no name', () {
      final row = PricedLine.of('SCE0833 1.000 50.00 50.00')!;

      expect(row.isCodeRow, isTrue);
      expect(row.code, 'SCE0833');
      expect(
        row.toItem(),
        const ReceiptLineItem(
          name: 'SCE0833',
          unitPriceCents: 5000,
          totalPriceCents: 5000,
        ),
      );
    });

    test('a name with a code in it, or a word with digits, is not one', () {
      expect(
        PricedLine.of('1 126285 SAFEGUARD SOAP 1.0 350.00 350.00')!.isCodeRow,
        isFalse,
      );
      expect(PricedLine.of('COOL 500.00')!.isCodeRow, isFalse);
      expect(PricedLine.of('B12 500.00')!.isCodeRow, isFalse);
    });

    test('its figures are dropped from the name whether or not they make '
        'the amount', () {
      final row = PricedLine.of('FT30317 ).170 1,560.00 249.60')!;

      expect(row.toItem()!.name, 'FT30317');
      expect(row.toItem()!.unitPriceCents, isNull);
    });
  });

  group('a column figure', () {
    test('is read through what OCR does to one', () {
      expect(PricedLine.columnNumber(').160'), '0.160');
      expect(PricedLine.columnNumber('O.160'), '0.160');
      expect(PricedLine.columnNumber('1,56O.00'), '1560.00');
      expect(PricedLine.columnNumber('1.560.00'), '1560.00');
      expect(PricedLine.columnNumber('120,00'), '120.00');
      expect(PricedLine.columnNumber('1000'), '1000');
      expect(PricedLine.columnNumber('S.B'), isNull);
    });
  });

  group('the quantity', () {
    final mandarin = PricedLine.of('X 249.60')!;

    test('is as read when it makes the amount', () {
      expect(mandarin.quantityFor('0.160', 156000), 0.16);
    });

    test('is the amount\'s when OCR lost or moved the point', () {
      expect(PricedLine.of('X 50.00')!.quantityFor('1000', 5000), 1.0);
      expect(mandarin.quantityFor('0160', 156000), 0.16);
      expect(mandarin.quantityFor('160', 156000), 0.16);
    });

    test('is nothing when no reading of its digits makes the amount', () {
      expect(mandarin.quantityFor('0.170', 156000), isNull);
      expect(PricedLine.of('X 650.00')!.quantityFor('200', 65000), isNull);
    });
  });
}
