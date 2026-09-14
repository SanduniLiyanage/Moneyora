import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/parsed_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parse_receipt_text.dart';

// Every fixture below is hand-written to a receipt shape, not read off a
// photo. They pin the parser's rules; they say nothing about its accuracy
// on real receipts, which needs the ROADMAP's 20–30 photos.

/// A grocery bill: address and phone in the header, a two-line item as
/// ML Kit reads one, a discount, a sub-total, VAT, and the cash tendered.
const supermarket = '''
KEELLS SUPER
NO 12, GALLE ROAD, COLOMBO 03
TEL: 011 2345678
VAT NO: 123456789-7000
Bill No: 4521    03/04/2026 14:32

RICE 5KG            1,250.00
MILK 1L
   2 x 240.00         480.00
BREAD                 180.00
SHAMPOO 200ML         650.00
DISCOUNT              -50.00
SUB TOTAL           2,510.00
VAT 15%               376.50
TOTAL               2,886.50
CASH                3,000.00
CHANGE                113.50
TOTAL ITEMS 5
THANK YOU COME AGAIN
''';

/// A pharmacy: `Rs` prefixes, a `/-` suffix, `x2` and `3 @ 45.00`
/// quantities, a date in words, and "NET AMOUNT" as the total label.
const pharmacy = '''
TAX INVOICE
HEALTHGUARD PHARMACY
Receipt No. HG-00917
Date: 12 Mar 2026
PANADOL 500MG x2        Rs 120.00
VITAMIN C 1000MG        Rs. 450/-
AMOXICILLIN 250MG 3 @ 45.00 135.00
NET AMOUNT              Rs 705.00
PAID BY CARD               705.00
''';

/// A restaurant check: table and covers in the header, an ISO date with
/// the time, leading quantities, a service charge, "GRAND TOTAL".
const restaurant = '''
THE CURRY LEAF RESTAURANT
Table 7   Pax 2
2026-04-18 20:15
2 x CHICKEN KOTTU     1,700.00
1 x LIME JUICE          350.00
WATER 500ML             120.00
SUBTOTAL              2,170.00
SERVICE CHARGE 10%      217.00
GRAND TOTAL           2,387.00
''';

ParsedReceipt parse(String text) =>
    ParseReceiptText.parse(RecognisedText.fromString(text));

void main() {
  group('the supermarket bill', () {
    final receipt = parse(supermarket);

    test('reads the header', () {
      expect(receipt.merchantName, 'KEELLS SUPER');
      expect(receipt.receiptDate, DateTime(2026, 4, 3, 14, 32));
      expect(receipt.receiptNumber, '4521');
    });

    test('reads every item and nothing else', () {
      expect(receipt.items, const [
        ReceiptLineItem(name: 'RICE 5KG', totalPriceCents: 125000),
        ReceiptLineItem(
          name: 'MILK 1L',
          quantity: 2,
          unitPriceCents: 24000,
          totalPriceCents: 48000,
        ),
        ReceiptLineItem(name: 'BREAD', totalPriceCents: 18000),
        ReceiptLineItem(name: 'SHAMPOO 200ML', totalPriceCents: 65000),
      ]);
    });

    test('reads the total and the tax, not the sub-total or the cash', () {
      expect(receipt.totalCents, 288650);
      expect(receipt.taxCents, 37650);
    });

    test('knows the items do not account for the total', () {
      expect(receipt.itemsSumCents, 256000);
      expect(receipt.itemsMatchTotal, isFalse);
    });
  });

  group('the pharmacy receipt', () {
    final receipt = parse(pharmacy);

    test('the title line is not the merchant', () {
      expect(receipt.merchantName, 'HEALTHGUARD PHARMACY');
    });

    test('reads a receipt number with letters and a date in words', () {
      expect(receipt.receiptNumber, 'HG-00917');
      expect(receipt.receiptDate, DateTime(2026, 3, 12));
    });

    test('reads Rs, /-, x2 and 3 @ 45.00', () {
      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'PANADOL 500MG',
          quantity: 2,
          unitPriceCents: 6000,
          totalPriceCents: 12000,
        ),
        ReceiptLineItem(name: 'VITAMIN C 1000MG', totalPriceCents: 45000),
        ReceiptLineItem(
          name: 'AMOXICILLIN 250MG',
          quantity: 3,
          unitPriceCents: 4500,
          totalPriceCents: 13500,
        ),
      ]);
    });

    test('NET AMOUNT is the total, the card line is not an item', () {
      expect(receipt.totalCents, 70500);
      expect(receipt.taxCents, isNull);
      expect(receipt.itemsMatchTotal, isTrue);
    });
  });

  group('the restaurant check', () {
    final receipt = parse(restaurant);

    test('skips the table line and reads the ISO date with its time', () {
      expect(receipt.merchantName, 'THE CURRY LEAF RESTAURANT');
      expect(receipt.receiptDate, DateTime(2026, 4, 18, 20, 15));
      expect(receipt.receiptNumber, isNull);
    });

    test('reads leading quantities and derives an exact unit price', () {
      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'CHICKEN KOTTU',
          quantity: 2,
          unitPriceCents: 85000,
          totalPriceCents: 170000,
        ),
        ReceiptLineItem(
          name: 'LIME JUICE',
          quantity: 1,
          totalPriceCents: 35000,
        ),
        ReceiptLineItem(name: 'WATER 500ML', totalPriceCents: 12000),
        ReceiptLineItem(name: 'SERVICE CHARGE 10%', totalPriceCents: 21700),
      ]);
    });

    test('GRAND TOTAL is the total and the items add up to it', () {
      expect(receipt.totalCents, 238700);
      expect(receipt.itemsMatchTotal, isTrue);
    });
  });

  group('amounts', () {
    test('are integer cents from the printed digits', () {
      final receipt = parse('SHOP\nA 1,234.56\nB 7.5\nC 12\nTOTAL 1,254.06');

      expect(receipt.items.map((i) => i.totalPriceCents), [123456, 750, 1200]);
    });

    test('a whole-rupee figure is a price inside the body only', () {
      final receipt = parse('SHOP\nBRANCH 12\nRICE 1250.00\nBREAD 180');

      expect(receipt.merchantName, 'SHOP');
      expect(receipt.items.map((i) => i.name), ['RICE', 'BREAD']);
      expect(receipt.items.last.totalPriceCents, 18000);
    });

    test('a negative line is not an item', () {
      final receipt = parse(
        'SHOP\nRICE 1250.00\nLOYALTY -125.00\nTOTAL 1125.00',
      );

      expect(receipt.items.map((i) => i.name), ['RICE']);
    });
  });

  group('the total', () {
    test('is the last total-labelled line', () {
      final receipt = parse('SHOP\nA 100.00\nSUB TOTAL 100.00\nTOTAL 115.00');

      expect(receipt.totalCents, 11500);
    });

    test('TOTAL VAT is a tax figure, not the total', () {
      final receipt = parse('SHOP\nA 100.00\nTOTAL VAT 15.00\nTOTAL 115.00');

      expect(receipt.taxCents, 1500);
      expect(receipt.totalCents, 11500);
    });

    test('a label on its own line joins the figure beneath it', () {
      final receipt = parse('SHOP\nEGGS 10 PCS 380.00\nTOTAL\n380.00');

      expect(receipt.totalCents, 38000);
      expect(receipt.items.single.quantity, 10);
      expect(receipt.items.single.unitPriceCents, 3800);
    });

    test('priced lines after it are never items', () {
      final receipt = parse('SHOP\nA 100.00\nTOTAL 100.00\nGIFT WRAP 50.00');

      expect(receipt.items.map((i) => i.name), ['A']);
    });
  });

  group('the tax', () {
    test('is the first tax-labelled figure', () {
      final receipt = parse(
        'SHOP\nA 100.00\nVAT 15% 15.00\nSSCL 2.5% 2.50\nTOTAL 117.50',
      );

      expect(receipt.taxCents, 1500);
    });

    test('a VAT registration number is not a figure', () {
      final receipt = parse('SHOP\nVAT NO 123456789\nA 100.00\nTOTAL 100.00');

      expect(receipt.taxCents, isNull);
      expect(receipt.items.length, 1);
    });
  });

  group('two-line items', () {
    test('a name joins the wordless priced line beneath it', () {
      final receipt = parse('SHOP\nRICE 5KG\n1,250.00\nTOTAL 1,250.00');

      expect(receipt.items, const [
        ReceiptLineItem(name: 'RICE 5KG', totalPriceCents: 125000),
      ]);
    });

    test('a priced line with its own words drops a heading above it', () {
      final receipt = parse('SHOP\nGROCERY\nRICE 5KG 1,250.00');

      expect(receipt.items.single.name, 'RICE 5KG');
    });

    test('the merchant line never joins', () {
      final receipt = parse('RICE 5KG\n1,250.00\nTOTAL 1,250.00');

      expect(receipt.merchantName, 'RICE 5KG');
      expect(receipt.items, isEmpty);
      expect(receipt.totalCents, 125000);
    });
  });

  group('quantities', () {
    test('a unit price is derived only when the division is exact', () {
      final receipt = parse('SHOP\n3 x SAMOSA 100.00\n2 x BUN 90.00');

      expect(receipt.items.first.quantity, 3);
      expect(receipt.items.first.unitPriceCents, isNull);
      expect(receipt.items.last.unitPriceCents, 4500);
    });

    test('a weight is a fractional quantity with a stated unit price', () {
      final receipt = parse('SHOP\nTOMATO 1.5 kg x 320.00 480.00');

      expect(
        receipt.items.single,
        const ReceiptLineItem(
          name: 'TOMATO',
          quantity: 1.5,
          unitPriceCents: 32000,
          totalPriceCents: 48000,
        ),
      );
    });

    test('x followed by a price is not a count', () {
      final receipt = parse('SHOP\nMILK x 240.00 240.00');

      expect(receipt.items.single.quantity, 1);
      expect(receipt.items.single.totalPriceCents, 24000);
    });
  });

  group('dates', () {
    test('a numeric date is day-first', () {
      expect(
        parse('SHOP\n03/04/2026\nA 1.00').receiptDate,
        DateTime(2026, 4, 3),
      );
      expect(parse('SHOP\n03-04-26\nA 1.00').receiptDate, DateTime(2026, 4, 3));
      expect(parse('SHOP\n3.4.2026\nA 1.00').receiptDate, DateTime(2026, 4, 3));
    });

    test('a time with am/pm is read on the 24-hour clock', () {
      expect(
        parse('SHOP\n03/04/2026 2:05 PM\nA 1.00').receiptDate,
        DateTime(2026, 4, 3, 14, 5),
      );
      expect(
        parse('SHOP\n03/04/2026 12:05 AM\nA 1.00').receiptDate,
        DateTime(2026, 4, 3, 0, 5),
      );
    });

    test('an impossible date is not a date', () {
      expect(parse('SHOP\n31/02/2026\nA 1.00').receiptDate, isNull);
    });

    test('the first date found is kept', () {
      final receipt = parse('SHOP\n03/04/2026\nEXPIRES 09/09/2027\nA 1.00');

      expect(receipt.receiptDate, DateTime(2026, 4, 3));
    });
  });

  group('the receipt number', () {
    test('needs a digit, so INVOICE TOTAL is not one', () {
      final receipt = parse('SHOP\nA 100.00\nINVOICE TOTAL 100.00');

      expect(receipt.receiptNumber, isNull);
      expect(receipt.totalCents, 10000);
    });

    test('is read from the common labels', () {
      expect(parse('SHOP\nINV# A-0042\nA 1.00').receiptNumber, 'A-0042');
      expect(parse('SHOP\nBill 000123\nA 1.00').receiptNumber, '000123');
      expect(parse('SHOP\nTxn ID: 77\nA 1.00').receiptNumber, '77');
    });
  });

  group('the use case', () {
    const parser = ParseReceiptText();

    test('returns the parse', () async {
      final result = await parser(RecognisedText.fromString(restaurant));

      expect(
        result.map((r) => r.totalCents),
        const Right<Failure, int?>(238700),
      );
    });

    test('nothing usable is an OcrFailure', () async {
      expect(
        await parser(const RecognisedText([])),
        const Left<Failure, ParsedReceipt>(OcrFailure()),
      );
      expect(
        await parser(RecognisedText.fromString('  \nTHANK YOU\n')),
        const Left<Failure, ParsedReceipt>(OcrFailure()),
      );
    });

    test('a total with no readable items is a parse, not a failure', () async {
      final result = await parser(
        RecognisedText.fromString('SHOP\nTOTAL 50.00'),
      );

      expect(result.isRight(), isTrue);
    });
  });

  group('RecognisedText', () {
    test('splits on line breaks and knows when it is blank', () {
      expect(RecognisedText.fromString('a\nb').lines, ['a', 'b']);
      expect(RecognisedText.fromString(' \n\t').isBlank, isTrue);
      expect(RecognisedText.fromString('a').isBlank, isFalse);
    });
  });

  group('ParsedReceipt', () {
    test('itemsMatchTotal is unknown without a total', () {
      const receipt = ParsedReceipt(
        items: [ReceiptLineItem(name: 'A', totalPriceCents: 100)],
      );

      expect(receipt.itemsSumCents, 100);
      expect(receipt.itemsMatchTotal, isNull);
    });
  });
}
