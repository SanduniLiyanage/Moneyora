import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_header_reader.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_vocabulary.dart';

ReceiptHeader read(String text, {Duration? localOffset}) => ReceiptHeaderReader(
  ReceiptVocabulary.standard,
  localOffset: localOffset,
).read(text.split('\n'));

void main() {
  group("the phone's and the email's text", () {
    const screenshot =
        '19:14 ! 4G 39\n'
        '<\n'
        '- Forwarded message\n'
        'From: Keells E-Bills <web.jms@keells.com>\n'
        'To: tester@example.com\n'
        'Cc:\n'
        'Bcc:\n'
        'Date: Mon, 05 Oct 2026 11:26:04 +0000 (UTC)\n'
        'Subject: Keells E-Bill | 05-Oct-2026 at Keells - Katubedda\n'
        'Bill Date :05-Oct-2026\n'
        'TEA 100.00';

    test('is set aside, every line of it', () {
      expect(
        read(screenshot).consumed,
        containsAll([0, 1, 2, 3, 4, 5, 6, 7, 8]),
      );
    });

    test('gives no field while the receipt gives its own', () {
      final header = read(screenshot);

      expect(header.receiptDate, DateTime(2026, 10, 5));
      expect(header.dateGuessed, isFalse);
    });

    test('the email header block ends at its subject', () {
      final header = read(
        'From: a@b.example\nSubject: bill\nTo: pay 100.00\nSHOP\nTEA 100.00',
      );

      expect(header.consumed, isNot(contains(2)));
    });

    test('a clock below the first two lines is not a status bar', () {
      final header = read('SHOP\nBRANCH\n9:41 AM\nTEA 100.00');

      expect(header.consumed, isNot(contains(2)));
    });
  });

  group('the merchant', () {
    test('is the labelled store, its dash tidied', () {
      final header = read(
        'WELCOME\nBilled Store : Keells- Katubedda\nTEA 100.00',
      );

      expect(header.merchantName, 'Keells - Katubedda');
      expect(header.merchantGuessed, isFalse);
    });

    test('a store address or phone is not a store label', () {
      final header = read(
        'GREEN LEAF\nStore Address : No.1, Main Street\n'
        'Store Mobile : 0771234567\nTEA 100.00',
      );

      expect(header.merchantName, 'GREEN LEAF');
    });

    test('is the first line above the items that reads as a name', () {
      expect(
        read('TAX INVOICE\nHEALTHGUARD\nTEA 100.00').merchantName,
        'HEALTHGUARD',
      );
      expect(
        read('12 34\n!!\nCORNER SHOP\nTEA 100.00').merchantName,
        'CORNER SHOP',
      );
    });

    test('a total printed above the items does not end the header', () {
      expect(
        read('Your bill: 535.00\nCORNER SHOP\nTEA 100.00').merchantName,
        'CORNER SHOP',
      );
    });

    test(
      'tidyName spaces a dash OCR closed up, and keeps one inside a name',
      () {
        expect(
          ReceiptHeaderReader.tidyName('Keells- Katubedda'),
          'Keells - Katubedda',
        );
        expect(
          ReceiptHeaderReader.tidyName('Keells -Katubedda'),
          'Keells - Katubedda',
        );
        expect(ReceiptHeaderReader.tidyName('7-ELEVEN.'), '7-ELEVEN');
      },
    );
  });

  group('the date', () {
    test('from the email only when the receipt has none, in local time', () {
      final header = read(
        'From: Shop <a@shop.example>\n'
        'Date: Mon, 05 Oct 2026 11:26:04 +0000 (UTC)\n'
        'Subject: bill\n'
        'TEA 100.00',
        localOffset: const Duration(hours: 5, minutes: 30),
      );

      expect(header.receiptDate, DateTime(2026, 10, 5, 16, 56, 4));
      expect(header.dateGuessed, isTrue);
      expect(header.merchantName, 'Shop');
      expect(header.merchantGuessed, isTrue);
    });

    test('takes its time from a labelled time line anywhere', () {
      final header = read(
        'SHOP\nBill Date : 05-Oct-2026\nTEA 100.00\nBilled Time : 4:54:43 PM',
      );

      expect(header.receiptDate, DateTime(2026, 10, 5, 16, 54, 43));
      expect(header.consumed, containsAll([1, 3]));
    });

    test('shares a line with the receipt number', () {
      final header = read('SHOP\nBill No: 4521 03/04/2026 14:32\nTEA 1.00');

      expect(header.receiptNumber, '4521');
      expect(header.receiptDate, DateTime(2026, 4, 3, 14, 32));
    });
  });

  group('the receipt number', () {
    test('is never a price', () {
      final header = read('SHOP\nYour bill for this transaction: 535.00');

      expect(header.receiptNumber, isNull);
    });
  });
}
