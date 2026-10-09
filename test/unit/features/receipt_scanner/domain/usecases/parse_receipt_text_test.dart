import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/parsed_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/payment_method.dart';
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

/// The first real receipt the parser met (2026-09-16, a Colombo boutique),
/// transcribed from the print. Three-line items — name, article code, then
/// `PRICE X QTY AMOUNT` — a `SUB TOTAL` with no `TOTAL` after it, the card
/// line, the time on its own line, and a "Saved Value" that is not an
/// item. Every rule it broke is named beside the test that pins the fix.
const boutique = '''
La Vivente
No:125, Srimath Anagarika Dharmapala mw
Colombo 07
TEL: 0112 335 773
www.lavivente.lk
Date : 20/08/2026 Operator: UPEKSHA
Bill No : 00000026 Unit : 1
Ln Product Price Qty Amount
S/M 0142
01 CASUAL TOP EV002
2000167-BLK/XS
2790.00 X 1 2790.00
02 1010002 M BAG 12X17
0.01 X 1 0.01
SPECIAL DISCOUNT 50% -0.01
SUB TOTAL 2790.00
MASTER CARD 2790.00
NO OF QTY SOLD : 2
TIME : 05:12:13 PM
Saved Value : 0.01
Card No : 1446 BOC
''';

/// The same receipt as ML Kit actually read it (bill1.jpg on the emulator,
/// 2026-09-16, the `[receipt-ocr]` rows verbatim): the merchant misread,
/// `Bill` as `Bil|`, the bag's quantity lost (`0.01 X 0.01`) and its
/// "Saved Value" label lost too. The transcription above pins the rules;
/// this pins that the rules survive what OCR does to the print.
const boutiqueAsRead = '''
La Viventey
No:125, Srimath Anagar ika Dha rmapa la mw
Colombo 07
TEL: 0112 335 773
WWw.lavivente. Ik
Date : 20/08/2026 Operator: UPEKSHA
Bil| No: 00000026 Unit 1
Ln Product Price Qty Amount
S/M 0142
01 CASUAL TOP EVO02
2000167-BLK/XS
2790.00 X 1 2790.00
02 1010002 M BAG 12X17
0.01 X 0.01
SPECIAL DISCOUNT 50% -0.01
SUB TOTAL 2790.00
MASTER CARD 2790.00
NO OF QTY sOLD : 2
TIME : 05:12:13 PM
0.01
Card No : 1446 BOC
''';

/// A Keells e-bill, forwarded by email and scanned as a phone screenshot
/// (2026-10-09), transcribed from the screenshot: the phone's status bar,
/// the email's header with its UTC date, then the bill — a total above the
/// table, a name wrapped onto a second line, the discounts as a block
/// naming each item by row and code, then gross, net, points, cash and
/// change. The recipient's address and loyalty number are replaced.
const keellsEBill = '''
19:14 !! 4G 39
<
---------- Forwarded message ---------
From: Keells E-Bills <web.jms@keells.com>
To: tester@example.com
Cc:
Bcc:
Date: Mon, 05 Oct 2026 11:26:04 +0000 (UTC)
Subject: Keells E-Bill | 05-Oct-2026 at Keells - Katubedda
Bill Date : 05-Oct-2026
Billed Time : 16:54:43
Billed Store : Keells - Katubedda
Store Address : No.78,Bandaranayaka Road,Katubedda
Bill No : 1661604
Nexus No : 1121050000000000
Cashier ID : 66003516
Store Mobile : 0761 613504 / 0112 303 500
Your bill for this transaction: 535.00
# Item Description Qty Price Amount
1 126285 SAFEGUARD SOAP MULTIPACK 280G 1.0 350.00 350.00
4S
2 100334 CLOGARD TOOTHPASTE 200G 1.0 365.00 365.00
Discounts
Nexus Deals 25%
2 100334 25.20% Dis Rs: 92.00
1 126285 25.10% Dis Rs: 88.00
Total Gross Amount 715.00
Total Net Amount 535.00
Change Money Redemption of Points 3.48
Cash 600.00
Total Change 68.48
Let's save the environment together. Bring back your reusable bags when
shopping with us and get Rs. 6 discount for each bag.
''';

/// The same e-bill as ML Kit read it on the emulator (2026-10-09, the
/// `[receipt-ocr]` rows verbatim but for the same two replacements): the
/// soap's `4S` lost, `Qty` as `Oty`, `92.00` as `92,00`, and the store as
/// `Keells- Katubedda`.
const keellsEBillAsRead = '''
19:14 ! 4G 39
<
- Forwarded message
From: Keells E-Bills <web.jms@keells.com>
To: tester@example.com
Cc:
Bcc:
Date: Mon, 05 Oct 2026 11:26:04 +0000 (UTC)
Subject: Keells E-Bill| | 05-Oct-2026 at Keells - Katubedd
Bill Date :05-Oct-2026
Billed Time :16:54:43
Billed Store : Keells- Katubedda
Store Address : No.78, Bandaranayaka Road,Katubedda
Bill No : 1661604
Nexus No : 1121050000000000
Cashier ID :66003516
Store Mobile :0761 613504 / 0112 303 500
Your bill for this transaction: 535.00
# Item Description Oty Price Amount
1 126285 SAFEGUARD SOAP MULTIPACK 280G 1.0 350.00 350.00
2 100334 CLOGARD TOOTHPASTE 200G 1.0 365.00 365.00
Discounts
Nexus Deals 25%
2 100334 25.20% Dis Rs: 92,00
1 126285 25.10% Dis Rs: 88.00
Total Gross Amount 715.00
Total Net Amount 535.00
Change Money Redemption of Points 3.48
Cash 600.00
Total Change 68.48
Let's save the environment together. Bring back your reusable bags when
shopping with us and get Rs. 6 discount for each bag.
- Requests for tax invoices must be submitted within 14 days from the
will not be accommoc
- Please use this bill as a reference if you have any price discrepancies
from today
Thic
''';

/// A discount on the whole bill, printed after the sub-total with no item
/// named: 50.00 over 310.00, 455.50 and 230.00 does not divide evenly.
const billDiscount = '''
GREEN LEAF MART
08/10/2026 18:40
SUGAR 1KG 310.00
TEA 100G 455.50
BISCUITS 230.00
SUB TOTAL 995.50
BILL DISCOUNT 50.00
NET TOTAL 945.50
CASH 1,000.00
CHANGE 54.50
''';

/// No discounts: a row number, quantity and price columns with no `x`, a
/// count, a multiplied quantity, a weight with `x` and a weight without.
const noDiscounts = '''
SUNRISE GROCERS
Bill No: 7781 08/10/2026 09:05
DHAL 1KG 1.0 395.00 395.00
EGGS 10 PCS 450.00
COCONUT 3 x 120.00 360.00
TOMATO 0.500 kg x 480.00 240.00
CARROT 0.350 1,200.00 420.00
TOTAL 1,865.00
VISA 1,865.00
''';

/// A line the vocabulary does not know — `AMOUNT` — that repeats the
/// items above it, and a total label OCR misread, so the total comes from
/// the cash and the change.
const summaryAsItem = '''
CITY PHARMACY
Date: 06/10/2026
PARACETAMOL 500MG 2 x 40.00 80.00
VITAMIN C 1000MG 450.00
AMOUNT 530.00
T0TAL 530.00
CASH 1,000.00
CHANGE 470.00
''';

/// A screenshot of a receipt: the phone's status bar and the app's back
/// arrow above the shop's name.
const behindStatusBar = '''
9:41 LTE 87
<
SUNRISE BAKERY
No. 14, Temple Road, Kandy
Tel: 081 222 3344
07/10/2026 08:15
FISH BUN 2 x 90.00 180.00
TEA 60.00
TOTAL 240.00
CASH 500.00
BALANCE 260.00
''';

/// A Cargills Food City till receipt, a camera photo of crumpled thermal
/// paper with its left edge cropped (2026-10-10). RECONSTRUCTED from what
/// the tester's app showed and from the photo — not the raw OCR dump. The
/// crop took the day off the bill's own date; ML Kit misread a quantity
/// (`).160`), a price (`1,56O.00`) and the Net Total label (`Net Totai`).
/// Each item is two lines: the name, then `CODE QTY PRICE AMOUNT`. Below
/// the payment, a Star Points block has a `Total:` of its own.
const cargillsPhoto = '''
CARGILLS FOOD CITY
Express Oval View Residence
0113-484489
07/2026 14:31:32 CASHIER No: 143
ITEM QTY PRICE AMOUNT
CHUPA CHUPS GUM FILL. LOLLIPOP
SCE0833 1.000 50.00 50.00
REVELLO KRUNCH W MILKY CARAMEL
SCE1166 1.000 120.00 120.00
IMPORTED MANDARIN
FT30317 ).160 1,56O.00 249.60
ANCHOR YOGHURT LOWFAT S.B
DYD3016 1.000 180.00 180.00
Sub Total 599.60
Net Totai 599.60
CARD 599.60
Balance 0.00
Time End: 14:31:32
Loyalty Customer
Name: Loyalty Customer
Star Points
As @ 10-07-2026 14:31 180.02
Earned on this bill: .60
Total: 180.62
IMPORTANT NOTICE
In case of a price discrepancy, return
the item & bill within 7 days to
refund the difference
Please call our hotline 0117 181 181 for
your valued suggestions and comments.
''';

/// The same photo as ML Kit read it on the emulator (2026-10-10, the
/// `[receipt-ocr]` rows verbatim but for the cashier's name), from the
/// copy sent in chat — 545 px wide, so worse than the tester's phone read
/// it: the date cut to `2026` with its time misread as 14:41:32, a
/// quantity's point lost (`1000`), a comma for a point (`120,00`), `Sub
/// fotal`, Net Total split over two lines with `S` for `5`, and `ime End`.
const cargillsPhotoAsRead = '''
CARGILLS FOOD CITY
Kpress Cval View Residence
0113-484a89
2026 14:41:32 CASHIER No: 143
TEM QTY PRICE AMOUNT
CHUPA CHUPS GUM FILL. LOLLIPOP
SCEO833 1000 50.00 50.00
REVELLO KRUNCH W MILKY CARAMEL
SCE1166 1.000 120,00 120.00
IMPORTED MANDARIN
FT30317 ).160 1,560.00 249.60
ANCHOR VOGHURT LOWEAT S.B
DYD3016 1.000 180.00 180.00
Sub fotal 599.60
Net Tota
S99.60
CARD 599.60
Balance 0.00
ime End: 14:31:32
Loyalty Customer
Name: Loyalty Customer
blar Points
As @ 10-07-2026 14:31 180.02
Earned on this aill: 60
Total: 180.62
IMPORTANT NOTICE
In case of a price discrepancy, return
the item & bll within 7 days to
refund the differencée
Piease call our hotline 0117 181 181 for
your valued suggestions and comments.
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

    test('reads every item and nothing else, the discount off the last, '
        'and the VAT on top spread over them', () {
      // 376.50 is 15% of the 2,510.00 the items come to after the discount,
      // so each takes exactly 15%.
      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'RICE 5KG',
          totalPriceCents: 143750,
          chargesCents: 18750,
        ),
        ReceiptLineItem(
          name: 'MILK 1L',
          quantity: 2,
          unitPriceCents: 24000,
          totalPriceCents: 55200,
          chargesCents: 7200,
        ),
        ReceiptLineItem(
          name: 'BREAD',
          totalPriceCents: 20700,
          chargesCents: 2700,
        ),
        ReceiptLineItem(
          name: 'SHAMPOO 200ML',
          totalPriceCents: 69000,
          discountCents: 5000,
          chargesCents: 9000,
        ),
      ]);
    });

    test('reads the total and the tax, not the sub-total or the cash', () {
      expect(receipt.totalCents, 288650);
      expect(receipt.taxCents, 37650);
    });

    test('the cash tendered after the total says it was paid in cash', () {
      expect(receipt.paymentMethod, PaymentMethod.cash);
    });

    test('with the VAT spread, the items add up to the total paid', () {
      expect(receipt.itemsSumCents, 288650);
      expect(receipt.itemsMatchTotal, isTrue);
      expect(receipt.guessedFields, isEmpty);
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
      expect(receipt.paymentMethod, PaymentMethod.card);
    });
  });

  group('the restaurant check', () {
    final receipt = parse(restaurant);

    test('skips the table line and reads the ISO date with its time', () {
      expect(receipt.merchantName, 'THE CURRY LEAF RESTAURANT');
      expect(receipt.receiptDate, DateTime(2026, 4, 18, 20, 15));
      expect(receipt.receiptNumber, isNull);
    });

    test('reads leading quantities and derives an exact unit price; the '
        'service charge is spread over the items, not an item', () {
      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'CHICKEN KOTTU',
          quantity: 2,
          unitPriceCents: 85000,
          totalPriceCents: 187000,
          chargesCents: 17000,
        ),
        ReceiptLineItem(
          name: 'LIME JUICE',
          totalPriceCents: 38500,
          chargesCents: 3500,
        ),
        ReceiptLineItem(
          name: 'WATER 500ML',
          totalPriceCents: 13200,
          chargesCents: 1200,
        ),
      ]);
    });

    test('GRAND TOTAL is the total and the items add up to it', () {
      expect(receipt.totalCents, 238700);
      expect(receipt.itemsMatchTotal, isTrue);
    });

    test('nothing says how it was paid', () {
      expect(receipt.paymentMethod, isNull);
    });
  });

  group('the payment method', () {
    test('is read from an unpriced line that starts by saying so', () {
      expect(
        parse('SHOP\nTEA 100.00\nTOTAL 100.00\nPaid by: VISA').paymentMethod,
        PaymentMethod.card,
      );
      expect(
        parse('SHOP\nTEA 100.00\nPAYMENT MODE CASH').paymentMethod,
        PaymentMethod.cash,
      );
      expect(
        parse('SHOP\nTEA 100.00\nTender: Debit Card').paymentMethod,
        PaymentMethod.card,
      );
    });

    test('a line that merely mentions cash or a card is not the method', () {
      expect(parse('CASH BILL\nSHOP\nTEA 100.00').paymentMethod, isNull);
      expect(
        parse('SHOP\nTEA 100.00\nTOTAL 100.00\nCard No : 1446').paymentMethod,
        isNull,
      );
      expect(parse('SHOP\nCASHEW NUTS 100.00').paymentMethod, isNull);
    });

    test('PAID with no method named is not a method, and the first line '
        'that names one wins', () {
      expect(parse('SHOP\nTEA 100.00\nPAID 100.00').paymentMethod, isNull);
      expect(
        parse('SHOP\nTEA 100.00\nVISA 100.00\nCHANGE 0.00\nCASH 0.00')
            .paymentMethod,
        PaymentMethod.card,
      );
    });

    test('an unpriced payment line never joins the item beneath it', () {
      final receipt = parse('SHOP\nTEA 100.00\nPaid by cash\n50.00');
      expect(receipt.items.map((i) => i.name), ['TEA']);
      expect(receipt.paymentMethod, PaymentMethod.cash);
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

    test('a negative line is a discount on the item above it, not an item', () {
      final receipt = parse(
        'SHOP\nRICE 1250.00\nLOYALTY -125.00\nTOTAL 1125.00',
      );

      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'RICE',
          totalPriceCents: 112500,
          discountCents: 12500,
        ),
      ]);
      expect(receipt.itemsMatchTotal, isTrue);
    });
  });

  group('a camera photo misreads a figure. FR-RCP-005', () {
    test('a comma for the point', () {
      final receipt = parse('SHOP\nRICE 1,250,00\nBREAD 180,00\nTOTAL 1430,00');

      expect(receipt.items.map((i) => i.totalPriceCents), [125000, 18000]);
      expect(receipt.totalCents, 143000);
    });

    test('a gap beside the point', () {
      final receipt = parse('SHOP\nRICE 1250. 00\nBREAD 180 .00');

      expect(receipt.items.map((i) => i.totalPriceCents), [125000, 18000]);
    });

    test('a letter for a digit', () {
      final receipt = parse('SHOP\nBREAD 18O.OO\nMILK l20.00\nTOTAL 3OO.OO');

      expect(receipt.items.map((i) => i.totalPriceCents), [18000, 12000]);
      expect(receipt.totalCents, 30000);
    });

    test('a thousands comma, a word, a date and a time are left alone', () {
      final receipt = parse(
        'SHOP\n03.04.2026 14:32\nMILO 240.00\nRICE 1,250\nOIL.00 50.00',
      );

      expect(receipt.receiptDate, DateTime(2026, 4, 3, 14, 32));
      expect(receipt.items.map((i) => (i.name, i.totalPriceCents)), [
        ('MILO', 24000),
        ('RICE', 125000),
        ('OIL.00', 5000),
      ]);
    });

    test('a line priced at nothing is not an item', () {
      // A free bag, or a price misread as 00: left out for the review to
      // say what is missing, never posted as an expense of zero.
      final receipt = parse('SHOP\nRICE 1250.00\nBAG 0.00\nTOTAL 1250.00');

      expect(receipt.items.map((i) => i.name), ['RICE']);
    });
  });

  group('discounts', () {
    test('a discount label without the minus is still a discount', () {
      final receipt = parse('SHOP\nRICE 1250.00\nDISCOUNT 10% 125.00');

      expect(receipt.items.single.totalPriceCents, 112500);
    });

    test('a discount equal to the item above it cancels the item', () {
      final receipt = parse(
        'SHOP\nRICE 1250.00\nBAG 0.01\nSPECIAL DISCOUNT 50% -0.01\n'
        'TOTAL 1250.00',
      );

      expect(receipt.items.map((i) => i.name), ['RICE']);
      expect(receipt.itemsMatchTotal, isTrue);
    });

    test('a discount keeps the printed unit price and says what came off', () {
      final milk = parse('SHOP\nMILK 2 x 240.00 480.00\nDISC -75.01');

      expect(
        milk.items.single,
        const ReceiptLineItem(
          name: 'MILK',
          quantity: 2,
          unitPriceCents: 24000,
          totalPriceCents: 40499,
          discountCents: 7501,
        ),
      );
      expect(milk.items.single.printedCents, 48000);
    });

    test('a discount larger than the item above it is spread over every '
        'item in proportion, to the cent', () {
      final receipt = parse(
        'SHOP\nRICE 1000.00\nBREAD 100.00\nMILK 50.00\nPROMO -230.00\n'
        'TOTAL 920.00',
      );

      // 1000 : 100 : 50 of 230.00 is 200.00 : 20.00 : 10.00 exactly.
      expect(receipt.items.map((i) => i.totalPriceCents), [80000, 8000, 4000]);
      expect(receipt.itemsMatchTotal, isTrue);

      final uneven = parse(
        'SHOP\nA 10.00\nB 10.00\nC 10.00\nOFF -20.01\nTOTAL 9.99',
      );
      expect(uneven.itemsSumCents, 999);
    });

    test('a bill-wide discount that covers everything leaves no items', () {
      final receipt = parse('SHOP\nA 10.00\nB 5.00\nVOUCHER -15.00');

      expect(receipt.items, isEmpty);
    });

    test('TOTAL DISCOUNT and SAVED VALUE are summaries, never applied', () {
      final receipt = parse(
        'SHOP\nRICE 1250.00\nDISCOUNT -125.00\nTOTAL DISCOUNT 125.00\n'
        'SUB TOTAL 1125.00\nYOU SAVED 125.00\nTOTAL 1125.00',
      );

      expect(receipt.items.single.totalPriceCents, 112500);
      expect(receipt.itemsMatchTotal, isTrue);
    });

    test('a discount before any item, or after the total, changes nothing', () {
      final before = parse('SHOP\nDISCOUNT -50.00\nRICE 1250.00');
      expect(before.items.single.totalPriceCents, 125000);

      final after = parse('SHOP\nRICE 1250.00\nTOTAL 1250.00\nDISCOUNT -50.00');
      expect(after.items.single.totalPriceCents, 125000);
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

  group('the boutique receipt — the first real one', () {
    final receipt = parse(boutique);

    test('reads the header, with the time from its own line', () {
      expect(receipt.merchantName, 'La Vivente');
      expect(receipt.receiptDate, DateTime(2026, 8, 20, 17, 12, 13));
      expect(receipt.receiptNumber, '00000026');
    });

    test('a three-line item is one item, named without its line number '
        'and code, priced as PRICE X QTY', () {
      final top = receipt.items.single;
      expect(top.name, 'CASUAL TOP EV002 2000167-BLK/XS');
      expect(top.quantity, 1);
      expect(top.unitPriceCents, 279000);
      expect(top.totalPriceCents, 279000);
    });

    test('the 50% discount cancels the one-cent bag, so the items add up '
        'to the sub-total', () {
      expect(receipt.items.map((i) => i.name), isNot(contains('M BAG 12X17')));
      expect(receipt.itemsSumCents, 279000);
      expect(receipt.itemsMatchTotal, isTrue);
    });

    test('SUB TOTAL is the total when nothing says TOTAL, the card line '
        'ends the body, and Saved Value is not an item', () {
      expect(receipt.totalCents, 279000);
      expect(receipt.taxCents, isNull);
      expect(receipt.paymentMethod, PaymentMethod.card);
      expect(receipt.items.map((i) => i.name), isNot(contains('Saved Value')));
    });

    test('the discount cancels the bag whether or not OCR kept its minus', () {
      final lostMinus = parse(boutique.replaceFirst('-0.01', '0.01'));
      expect(lostMinus.items.map((i) => i.name), [
        'CASUAL TOP EV002 2000167-BLK/XS',
      ]);

      final dash = parse(boutique.replaceFirst('-0.01', '–0.01'));
      expect(dash.items.length, 1);
    });

    test('without the discount line the bag is an item and the sum is off '
        'by a cent, which the review screen is there to show', () {
      final undiscounted = parse(
        boutique.replaceFirst('SPECIAL DISCOUNT 50% -0.01\n', ''),
      );

      expect(undiscounted.items.map((i) => i.name), [
        'CASUAL TOP EV002 2000167-BLK/XS',
        'M BAG 12X17',
      ]);
      expect(undiscounted.itemsMatchTotal, isFalse);
    });

    test('the card figure is the total when there is no sub-total either, '
        'but cash tendered never is', () {
      final cardOnly = parse(boutique.replaceFirst('SUB TOTAL 2790.00\n', ''));
      expect(cardOnly.totalCents, 279000);

      final cash = parse(
        boutique
            .replaceFirst('SUB TOTAL 2790.00\n', '')
            .replaceFirst('MASTER CARD 2790.00', 'CASH 3000.00'),
      );
      expect(cash.totalCents, isNull);
      expect(cash.items.length, 1);
    });

    test('a column-title line never joins an item name', () {
      final receipt = parse(
        'SHOP\nDESCRIPTION QTY AMOUNT\nBREAD\n2 x 150.00 300.00',
      );
      expect(receipt.items.single.name, 'BREAD');
      expect(receipt.items.single.quantity, 2);
      expect(receipt.items.single.unitPriceCents, 15000);
    });

    test('a name that is only a code is kept rather than emptied', () {
      final receipt = parse('SHOP\n1234567 450.00 X 1 450.00\nTOTAL 450.00');
      expect(receipt.items.single.name, '1234567');
    });
  });

  group('the boutique receipt — as ML Kit read it', () {
    final receipt = parse(boutiqueAsRead);

    test('the header survives Bil| and a misread merchant', () {
      // The merchant is what OCR read; FR-RCP-008's review screen is where
      // a misread name is corrected, not the parser.
      expect(receipt.merchantName, 'La Viventey');
      expect(receipt.receiptDate, DateTime(2026, 8, 20, 17, 12, 13));
      expect(receipt.receiptNumber, '00000026');
    });

    test('one item, the bag cancelled, and the items add up to the total', () {
      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'CASUAL TOP EVO02 2000167-BLK/XS',
          unitPriceCents: 279000,
          totalPriceCents: 279000,
        ),
      ]);
      expect(receipt.totalCents, 279000);
      expect(receipt.itemsMatchTotal, isTrue);
      expect(receipt.paymentMethod, PaymentMethod.card);
    });

    test('a lost quantity after PRICE X is not part of the name', () {
      final undiscounted = parse(
        boutiqueAsRead.replaceFirst('SPECIAL DISCOUNT 50% -0.01\n', ''),
      );

      expect(
        undiscounted.items.last,
        const ReceiptLineItem(
          name: 'M BAG 12X17',
          unitPriceCents: 1,
          totalPriceCents: 1,
        ),
      );

      final two = parse('SHOP\nBREAD\n150.00 X 300.00\nTOTAL 300.00');
      expect(two.items.single.quantity, 2);
      expect(two.items.single.unitPriceCents, 15000);

      final inexact = parse('SHOP\nBREAD\n140.00 X 300.00\nTOTAL 300.00');
      expect(inexact.items.single.name, 'BREAD');
      expect(inexact.items.single.quantity, 1);
      expect(inexact.items.single.unitPriceCents, isNull);
    });
  });

  group('the Keells e-bill, transcribed', () {
    final receipt = parse(keellsEBill);

    test('reads the store, the bill number and the till time, not the '
        "phone's status bar or the email's UTC date", () {
      expect(receipt.merchantName, 'Keells - Katubedda');
      expect(receipt.receiptNumber, '1661604');
      expect(receipt.receiptDate, DateTime(2026, 10, 5, 16, 54, 43));
      expect(receipt.guessedFields, isEmpty);
    });

    test('the net amount is the total — not the change, the cash or the '
        'gross', () {
      expect(receipt.totalCents, 53500);
      expect(receipt.taxCents, isNull);
      expect(receipt.paymentMethod, PaymentMethod.cash);
    });

    test('two items, each less the discount that names its code, the '
        'wrapped 4S back on the soap', () {
      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'SAFEGUARD SOAP MULTIPACK 280G 4S',
          unitPriceCents: 35000,
          totalPriceCents: 26200,
          discountCents: 8800,
        ),
        ReceiptLineItem(
          name: 'CLOGARD TOOTHPASTE 200G',
          unitPriceCents: 36500,
          totalPriceCents: 27300,
          discountCents: 9200,
        ),
      ]);
    });

    test('the items add up to the total, so nothing is in doubt', () {
      expect(receipt.itemsSumCents, 53500);
      expect(receipt.itemsMatchTotal, isTrue);
    });

    test('reads the same without its profile: the Discounts heading is '
        'enough', () {
      final generic = ParseReceiptText.parse(
        RecognisedText.fromString(keellsEBill),
        profiles: const [],
      );

      expect(generic.items, receipt.items);
      expect(generic.totalCents, 53500);
    });
  });

  group('the Keells e-bill, as ML Kit read it', () {
    final receipt = parse(keellsEBillAsRead);

    test('the same header, the store tidied', () {
      expect(receipt.merchantName, 'Keells - Katubedda');
      expect(receipt.receiptNumber, '1661604');
      expect(receipt.receiptDate, DateTime(2026, 10, 5, 16, 54, 43));
    });

    test('the same items and total, the soap without the 4S OCR lost', () {
      expect(receipt.items.map((i) => (i.name, i.totalPriceCents)), [
        ('SAFEGUARD SOAP MULTIPACK 280G', 26200),
        ('CLOGARD TOOTHPASTE 200G', 27300),
      ]);
      expect(receipt.totalCents, 53500);
      expect(receipt.itemsMatchTotal, isTrue);
      expect(receipt.guessedFields, isEmpty);
    });
  });

  group('a discount on the whole bill', () {
    final receipt = parse(billDiscount);

    test('is shared over the items in proportion, the cent left over on the '
        'largest, and the items add up to the net total', () {
      // 50.00 of 995.50: 15.57, 22.87 and 11.55 rounded down leave a cent,
      // which the tea — the largest item — takes.
      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'SUGAR 1KG',
          totalPriceCents: 29443,
          discountCents: 1557,
        ),
        ReceiptLineItem(
          name: 'TEA 100G',
          totalPriceCents: 43262,
          discountCents: 2288,
        ),
        ReceiptLineItem(
          name: 'BISCUITS',
          totalPriceCents: 21845,
          discountCents: 1155,
        ),
      ]);
      expect(receipt.totalCents, 94550);
      expect(receipt.itemsMatchTotal, isTrue);
    });

    test('a rate with no amount is applied when that is what adds up, after '
        "an item's own discount", () {
      final receipt = parse(
        'SHOP\nSOAP 200.00\nDISCOUNT -20.00\nRICE 300.00\n'
        'SUB TOTAL 480.00\nDISCOUNT 10%\nTOTAL 432.00',
      );

      expect(receipt.items.map((i) => (i.totalPriceCents, i.discountCents)), [
        (16200, 3800),
        (27000, 3000),
      ]);
      expect(receipt.itemsMatchTotal, isTrue);
    });

    test('a discount naming an item code comes off that item alone', () {
      final receipt = parse(
        'SHOP\n1 1001 SOAP 1.0 200.00 200.00\n2 1002 RICE 1.0 300.00 300.00\n'
        '3 1003 MILK 1.0 150.00 150.00\nDISCOUNTS\n1003 PROMO 15.00\n'
        '1001 PROMO 20.00\nTOTAL 615.00',
      );

      expect(receipt.items.map((i) => (i.name, i.totalPriceCents)), [
        ('SOAP', 18000),
        ('RICE', 30000),
        ('MILK', 13500),
      ]);
      expect(receipt.itemsMatchTotal, isTrue);
    });
  });

  group('a receipt with no discounts', () {
    final receipt = parse(noDiscounts);

    test('reads quantities and prices in every printed form', () {
      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'DHAL 1KG',
          unitPriceCents: 39500,
          totalPriceCents: 39500,
        ),
        ReceiptLineItem(
          name: 'EGGS',
          quantity: 10,
          unitPriceCents: 4500,
          totalPriceCents: 45000,
        ),
        ReceiptLineItem(
          name: 'COCONUT',
          quantity: 3,
          unitPriceCents: 12000,
          totalPriceCents: 36000,
        ),
        ReceiptLineItem(
          name: 'TOMATO',
          quantity: 0.5,
          unitPriceCents: 48000,
          totalPriceCents: 24000,
        ),
        ReceiptLineItem(
          name: 'CARROT',
          quantity: 0.35,
          unitPriceCents: 120000,
          totalPriceCents: 42000,
        ),
      ]);
    });

    test('adds up, and was paid by card', () {
      expect(receipt.merchantName, 'SUNRISE GROCERS');
      expect(receipt.receiptNumber, '7781');
      expect(receipt.receiptDate, DateTime(2026, 10, 8, 9, 5));
      expect(receipt.totalCents, 186500);
      expect(receipt.itemsMatchTotal, isTrue);
      expect(receipt.paymentMethod, PaymentMethod.card);
    });

    test('a quantity and a price that do not make the amount are left in '
        'the name, the amount kept', () {
      final receipt = parse('SHOP\nSHAMPOO 200 650.00 650.00\nTOTAL 650.00');

      expect(receipt.items.single.name, 'SHAMPOO 200 650.00');
      expect(receipt.items.single.quantity, 1);
      expect(receipt.items.single.totalPriceCents, 65000);
    });
  });

  group('a summary line that looks like an item', () {
    final receipt = parse(summaryAsItem);

    test('is dropped because it repeats the items above it, and the cash '
        'less the change gives the total', () {
      expect(receipt.items.map((i) => (i.name, i.totalPriceCents)), [
        ('PARACETAMOL 500MG', 8000),
        ('VITAMIN C 1000MG', 45000),
      ]);
      expect(receipt.totalCents, 53000);
      expect(receipt.itemsMatchTotal, isTrue);
      expect(receipt.guessedFields, isEmpty);
    });

    test(
      'a known summary label is never an item, above the items or below',
      () {
        final receipt = parse(
          'SHOP\nBill Amount: 300.00\nTEA 100.00\nRICE 200.00\n'
          'Amount Due 300.00\nCASH 500.00\nBALANCE 200.00',
        );

        expect(receipt.items.map((i) => i.name), ['TEA', 'RICE']);
        expect(receipt.totalCents, 30000);
      },
    );

    test('when nothing adds up, the receipt is shown as printed and says '
        'so', () {
      final receipt = parse('SHOP\nTEA 100.00\nRICE 200.00\nTOTAL 350.00');

      expect(receipt.items.length, 2);
      expect(receipt.totalCents, 35000);
      expect(receipt.itemsMatchTotal, isFalse);
    });

    test('a total worked out from the cash and change alone is a guess', () {
      final receipt = parse('SHOP\nTEA 100.00\nCASH 500.00\nCHANGE 350.00');

      expect(receipt.totalCents, 15000);
      expect(receipt.guessedFields, {ReceiptField.total});
    });
  });

  group("the phone's own text above the receipt", () {
    final receipt = parse(behindStatusBar);

    test('is never the merchant or an item', () {
      expect(receipt.merchantName, 'SUNRISE BAKERY');
      expect(receipt.receiptDate, DateTime(2026, 10, 7, 8, 15));
      expect(receipt.items.map((i) => i.name), ['FISH BUN', 'TEA']);
      expect(receipt.totalCents, 24000);
      expect(receipt.itemsMatchTotal, isTrue);
    });

    test('on Android too, whose icons OCR reads as letters', () {
      expect(parse('2:32 9 O\nSHOP\nTEA 100.00').merchantName, 'SHOP');
      expect(parse('12:01 @ M\nSHOP\nTEA 100.00').merchantName, 'SHOP');
    });

    test('a merchant that cannot be read is left blank, not filled with '
        'noise', () {
      final receipt = parse('19:14 !!4G39\n<\n1.50\nTEA 100.00\nTOTAL 100.00');

      expect(receipt.merchantName, isNull);
      expect(receipt.items.single.name, 'TEA');
    });

    test('a time on the first line is the receipt\'s when it has a date', () {
      final receipt = parse('14:32 03/04/2026\nSHOP\nTEA 100.00');

      expect(receipt.receiptDate, DateTime(2026, 4, 3, 14, 32));
      expect(receipt.merchantName, 'SHOP');
    });
  });

  group('a receipt in an email', () {
    const forwarded =
        '---------- Forwarded message ---------\n'
        'From: Green Leaf Mart <bills@greenleaf.example>\n'
        'Date: Thu, 08 Oct 2026 13:10:00 +0000\n'
        'Subject: Your bill\n'
        'TEA 100.00\n'
        'TOTAL 100.00';

    test("with no date of its own, takes the email's, in local time, as a "
        'guess', () {
      final receipt = ParseReceiptText.parse(
        RecognisedText.fromString(forwarded),
        localOffset: const Duration(hours: 5, minutes: 30),
      );

      expect(receipt.receiptDate, DateTime(2026, 10, 8, 18, 40));
      expect(receipt.guessedFields, contains(ReceiptField.date));
    });

    test("with no store of its own, takes the sender's name, as a guess", () {
      final receipt = parse(forwarded);

      expect(receipt.merchantName, 'Green Leaf Mart');
      expect(receipt.guessedFields, contains(ReceiptField.merchant));
    });

    test("a receipt's own Date: line is the bill's, not an email's", () {
      final receipt = parse('SHOP\nDate: 12 Mar 2026\nTEA 100.00');

      expect(receipt.receiptDate, DateTime(2026, 3, 12));
      expect(receipt.guessedFields, isEmpty);
    });
  });

  group('dates and times in the forms receipts print', () {
    test('read day-first, with words, with seconds, on either clock', () {
      expect(
        parse('SHOP\n2026-10-05 16:54:43\nA 1.00').receiptDate,
        DateTime(2026, 10, 5, 16, 54, 43),
      );
      expect(
        parse('SHOP\n05/10/2026 04:54 PM\nA 1.00').receiptDate,
        DateTime(2026, 10, 5, 16, 54),
      );
      expect(
        parse('SHOP\n5 October 2026\nA 1.00').receiptDate,
        DateTime(2026, 10, 5),
      );
    });

    test('a labelled bill date beats a date printed above it', () {
      final receipt = parse(
        'SHOP\nPrinted 06/10/2026\nBill Date : 05-Oct-2026\nTEA 100.00',
      );

      expect(receipt.receiptDate, DateTime(2026, 10, 5));
    });

    test('a date alone leaves the time empty', () {
      final receipt = parse('SHOP\nBill Date : 05-Oct-2026\nTEA 100.00');

      expect(receipt.receiptDate, DateTime(2026, 10, 5));
    });
  });

  group('the Keells profile', () {
    const till =
        'KEELLS SUPER\n'
        '1 126285 SAFEGUARD SOAP 1.0 350.00 350.00\n'
        '1 126285 25.10% Dis 88.00\n'
        'TOTAL 262.00';

    test('knows Dis is a discount, on a till receipt with no heading', () {
      final receipt = parse(till);

      expect(receipt.items.single.totalPriceCents, 26200);
      expect(receipt.items.single.discountCents, 8800);
    });

    test("without it, Dis is no word the parser knows, and the items don't "
        'add up', () {
      final receipt = ParseReceiptText.parse(
        RecognisedText.fromString(till),
        profiles: const [],
      );

      expect(receipt.itemsMatchTotal, isFalse);
    });

    test("changes nothing on another shop's receipt", () {
      expect(
        parse('SHOP\nDIS PLAY STAND 100.00\nTOTAL 100.00').items.single.name,
        'DIS PLAY STAND',
      );
    });
  });

  group('the Cargills photo, reconstructed', () {
    final receipt = parse(cargillsPhoto);

    test('reads the merchant, and the date from the points line when the '
        "bill's own lost its day, with the bill's own time", () {
      expect(receipt.merchantName, 'CARGILLS FOOD CITY');
      expect(receipt.receiptDate, DateTime(2026, 7, 10, 14, 31, 32));
      expect(receipt.paymentMethod, PaymentMethod.card);
    });

    test('the Net Total is the total, misread label and all — not the '
        "points block's Total", () {
      expect(receipt.totalCents, 59960);
      expect(receipt.taxCents, isNull);
    });

    test('four items, each named by the line above its code row', () {
      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'CHUPA CHUPS GUM FILL. LOLLIPOP',
          unitPriceCents: 5000,
          totalPriceCents: 5000,
        ),
        ReceiptLineItem(
          name: 'REVELLO KRUNCH W MILKY CARAMEL',
          unitPriceCents: 12000,
          totalPriceCents: 12000,
        ),
        ReceiptLineItem(
          name: 'IMPORTED MANDARIN',
          quantity: 0.16,
          unitPriceCents: 156000,
          totalPriceCents: 24960,
        ),
        ReceiptLineItem(
          name: 'ANCHOR YOGHURT LOWFAT S.B',
          unitPriceCents: 18000,
          totalPriceCents: 18000,
        ),
      ]);
    });

    test('they add up to the total, and nothing is in doubt', () {
      expect(receipt.itemsSumCents, 59960);
      expect(receipt.itemsMatchTotal, isTrue);
      expect(receipt.guessedFields, isEmpty);
    });
  });

  group('the Cargills photo, as ML Kit read it', () {
    final receipt = parse(cargillsPhotoAsRead);

    test('the same header, despite the cut date and the misread time', () {
      expect(receipt.merchantName, 'CARGILLS FOOD CITY');
      expect(receipt.receiptDate, DateTime(2026, 7, 10, 14, 31, 32));
      expect(receipt.paymentMethod, PaymentMethod.card);
    });

    test('the same items and total, the quantity and price repaired', () {
      expect(receipt.items, const [
        ReceiptLineItem(
          name: 'CHUPA CHUPS GUM FILL. LOLLIPOP',
          unitPriceCents: 5000,
          totalPriceCents: 5000,
        ),
        ReceiptLineItem(
          name: 'REVELLO KRUNCH W MILKY CARAMEL',
          unitPriceCents: 12000,
          totalPriceCents: 12000,
        ),
        ReceiptLineItem(
          name: 'IMPORTED MANDARIN',
          quantity: 0.16,
          unitPriceCents: 156000,
          totalPriceCents: 24960,
        ),
        ReceiptLineItem(
          name: 'ANCHOR VOGHURT LOWEAT S.B',
          unitPriceCents: 18000,
          totalPriceCents: 18000,
        ),
      ]);
      expect(receipt.totalCents, 59960);
      expect(receipt.itemsMatchTotal, isTrue);
      expect(receipt.guessedFields, isEmpty);
    });
  });

  group('a loyalty block below the bill', () {
    test('is not the bill: its Total is never the total, its figures never '
        'items', () {
      // No total line on the bill itself, so the block's Total: is the only
      // labelled total there is.
      final receipt = parse(
        'SHOP\nTEA 100.00\nRICE 200.00\nCASH 500.00\nCHANGE 200.00\n'
        'Loyalty Points\nOpening balance 1,000.00\n'
        'Earned on this bill: 3.00\nTotal: 1,003.00',
      );

      expect(receipt.totalCents, 30000);
      expect(receipt.items.map((i) => i.name), ['TEA', 'RICE']);
      expect(receipt.itemsMatchTotal, isTrue);
      expect(receipt.guessedFields, isEmpty);
    });

    test('nor is its date the date, while the bill prints one', () {
      final receipt = parse(
        'SHOP\n09/07/2026 18:02\nTEA 100.00\nTOTAL 100.00\nCASH 100.00\n'
        'Star Points\nAs @ 10-07-2026 14:31 180.02',
      );

      expect(receipt.receiptDate, DateTime(2026, 7, 9, 18, 2));
    });

    test('a loyalty word above the total is left alone', () {
      final receipt = parse(
        'SHOP\nTEA 100.00\nLOYALTY -10.00\nTOTAL 90.00\nThank you',
      );

      expect(receipt.totalCents, 9000);
      expect(receipt.items.single.totalPriceCents, 9000);
    });
  });

  group('a total label OCR misread', () {
    test('is still a total, never an item', () {
      for (final label in ['Net Totai', 'NET T0TAL', 'Net Tota', 'TOTA1']) {
        final receipt = parse('SHOP\nTEA 100.00\nRICE 200.00\n$label 300.00');

        expect(receipt.items.map((i) => i.name), [
          'TEA',
          'RICE',
        ], reason: label);
        expect(receipt.totalCents, 30000, reason: label);
      }
    });

    test('Sub fotal and S99.60 are the sub-total and a figure', () {
      final receipt = parse(
        'SHOP\nTEA 100.00\nRICE 499.60\nSub fotal 599.60\nNet Tota\nS99.60',
      );

      expect(receipt.items.length, 2);
      expect(receipt.totalCents, 59960);
    });

    test('a word that merely resembles one is not a label', () {
      final receipt = parse(
        'SHOP\nLIP GLOSS 450.00\nSERVICE CHARGE 10% 45.00\nTOTAL 495.00',
      );

      expect(receipt.items.single.name, 'LIP GLOSS');
      expect(receipt.items.single.chargesCents, 4500);
    });
  });

  group('item layouts', () {
    test('a name, then a code row, is one item named by the first line', () {
      final receipt = parse(
        'SHOP\nITEM QTY PRICE AMOUNT\nCHUPA CHUPS LOLLIPOP\n'
        'SCE0833 1.000 50.00 50.00\nTOTAL 50.00',
      );

      expect(receipt.items.single.name, 'CHUPA CHUPS LOLLIPOP');
      expect(receipt.items.single.quantity, 1);
      expect(receipt.items.single.unitPriceCents, 5000);
    });

    test('a name, code and figures on one line still read as before', () {
      final receipt = parse(
        'SHOP\n1 126285 SAFEGUARD SOAP 1.0 350.00 350.00\nTOTAL 350.00',
      );

      expect(receipt.items.single.name, 'SAFEGUARD SOAP');
      expect(receipt.items.single.unitPriceCents, 35000);
    });

    test('a code row with no name above keeps its code as the name', () {
      final receipt = parse('SHOP\nSCE0833 1.000 50.00 50.00\nTOTAL 50.00');

      expect(receipt.items.single.name, 'SCE0833');
    });
  });

  group('a weighed item with a misread quantity', () {
    test('is repaired when the repair makes the amount', () {
      final cases = {
        'FT30317 ).160 1,560.00 249.60': 0.16,
        'FT30317 O.160 1,560.00 249.60': 0.16,
        'FT30317 0.16O 1.560.00 249.60': 0.16,
        'SCE0833 1000 50.00 50.00': 1.0,
      };
      for (final MapEntry(key: row, value: quantity) in cases.entries) {
        final receipt = parse('SHOP\nIMPORTED MANDARIN\n$row\nTOTAL 999.99');

        expect(receipt.items.single.quantity, quantity, reason: row);
        expect(receipt.items.single.name, 'IMPORTED MANDARIN', reason: row);
      }
    });

    test('is left alone when no repair makes the amount', () {
      final receipt = parse(
        'SHOP\nIMPORTED MANDARIN\nFT30317 ).170 1,560.00 249.60',
      );

      expect(receipt.items.single.quantity, 1);
      expect(receipt.items.single.unitPriceCents, isNull);
      expect(receipt.items.single.totalPriceCents, 24960);
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
