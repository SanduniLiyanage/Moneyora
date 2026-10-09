import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/payment_method.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_body.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_body_reader.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_vocabulary.dart';

ReceiptBody read(String text, {ReceiptVocabulary? vocabulary}) =>
    ReceiptBodyReader(vocabulary ?? ReceiptVocabulary.standard)
        .read(text.split('\n'));

void main() {
  group('summary lines', () {
    const keellsTail =
        'Your bill for this transaction: 535.00\n'
        '1 126285 SOAP 1.0 350.00 350.00\n'
        '2 100334 TOOTHPASTE 1.0 365.00 365.00\n'
        'Total Gross Amount 715.00\n'
        'Total Net Amount 535.00\n'
        'Change Money Redemption of Points 3.48\n'
        'Cash 600.00\n'
        'Total Change 68.48';

    test('each say what they are, and none is an item', () {
      final body = read(keellsTail);

      expect(body.items.map((i) => i.item.name), ['SOAP', 'TOOTHPASTE']);
      expect(body.summaries, const [
        SummaryLine(LineRole.total, 53500),
        SummaryLine(LineRole.gross, 71500),
        SummaryLine(LineRole.net, 53500),
        SummaryLine(LineRole.points, 348),
        SummaryLine(LineRole.tender, 60000, method: PaymentMethod.cash),
        SummaryLine(LineRole.change, 6848, afterPayment: true),
      ]);
      expect(body.paymentMethod, PaymentMethod.cash);
    });

    test('the vocabulary sorts the lines receipts print', () {
      final roles = {
        'SUB TOTAL': LineRole.gross,
        'GRAND TOTAL': LineRole.net,
        'TOTAL INCL. VAT': LineRole.net,
        'TOTAL VAT': LineRole.tax,
        'SERVICE CHARGE 10%': LineRole.service,
        'AMOUNT DUE': LineRole.total,
        'BALANCE DUE': LineRole.total,
        'BALANCE': LineRole.change,
        'ROUND OFF': LineRole.rounding,
        'TOTAL ITEMS': LineRole.count,
        'YOU SAVED': LineRole.discountSummary,
        'MASTER CARD': LineRole.tender,
        'POINTS REDEEMED': LineRole.points,
      };
      for (final MapEntry(key: label, value: role) in roles.entries) {
        expect(ReceiptVocabulary.standard.roleOf(label), role, reason: label);
      }
      expect(ReceiptVocabulary.standard.roleOf('DISCOUNT ON TOTAL'), isNull);
      expect(ReceiptVocabulary.standard.roleOf('CASHEW NUTS'), isNull);
    });
  });

  group('discount lines', () {
    test('in a block name their item by row and code', () {
      final body = read(
        '1 126285 SOAP 1.0 350.00 350.00\n'
        'Discounts\n'
        '1 126285 25.10% Dis Rs: 88.00',
      );

      expect(body.items.single.code, '126285');
      expect(body.discounts, const [
        DiscountLine(
          cents: 8800,
          percent: 25.10,
          code: '126285',
          rowNumber: 1,
          listed: true,
        ),
      ]);
    });

    test('under an item belong to it; after the sub-total, to the bill', () {
      final body = read(
        'RICE 1250.00\nDISCOUNT -125.00\nSUB TOTAL 1125.00\nPROMO 25.00',
      );

      expect(body.discounts, const [
        DiscountLine(cents: 12500, belowItem: 0),
        DiscountLine(cents: 2500, onBill: true),
      ]);
    });

    test('a rate with no amount is kept for the reconciler', () {
      final body = read('RICE 1250.00\nSUB TOTAL 1250.00\nDISCOUNT 10%');

      expect(body.discounts, const [DiscountLine(percent: 10, onBill: true)]);
    });
  });

  group('names', () {
    test('a fragment under a numbered row ends its name', () {
      final body = read(
        '1 126285 SAFEGUARD SOAP 1.0 350.00 350.00\n'
        '4S\n'
        '2 100334 TOOTHPASTE 1.0 365.00 365.00',
      );

      expect(body.items.first.item.name, 'SAFEGUARD SOAP 4S');
      expect(body.items.first.rowNumber, 1);
    });

    test('a fragment before the totals ends the last row', () {
      final body = read(
        '1 1001 TEA BAGS 1.0 350.00 350.00\n100S\nTOTAL 350.00',
      );

      expect(body.items.single.item.name, 'TEA BAGS 100S');
    });

    test('a code row is named by the line above it, and keeps its code', () {
      final body = read(
        'TEM QTY PRICE AMOUNT\n'
        'CHUPA CHUPS GUM FILL. LOLLIPOP\n'
        'SCEO833 1000 50.00 50.00\n'
        'IMPORTED MANDARIN\n'
        'FT30317 ).160 1,56O.00 249.60',
      );

      expect(body.items.map((i) => (i.item.name, i.code, i.item.quantity)), [
        ('CHUPA CHUPS GUM FILL. LOLLIPOP', 'SCEO833', 1.0),
        ('IMPORTED MANDARIN', 'FT30317', 0.16),
      ]);
    });

    test('a misread total split over two lines is still the total', () {
      final body = read('TEA 599.60\nNet Tota\nS99.60\nCARD 599.60');

      expect(body.summaries.first, const SummaryLine(LineRole.net, 59960));
      expect(body.items.length, 1);
    });

    test('a total printed below the payment says so', () {
      final body = read('TEA 100.00\nCASH 100.00\nTOTAL 100.00');

      expect(
        body.summaries.last,
        const SummaryLine(LineRole.total, 10000, afterPayment: true),
      );
    });

    test('a line of words between unnumbered items is a heading', () {
      final body = read('RICE 250.00\nBAKERY\nBREAD 180.00');

      expect(body.items.map((i) => i.item.name), ['RICE', 'BREAD']);
    });
  });
}
