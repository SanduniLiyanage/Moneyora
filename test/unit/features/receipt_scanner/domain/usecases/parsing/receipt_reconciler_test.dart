import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_body.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_reconciler.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_vocabulary.dart';

ItemLine item(String name, int cents, {int? row, String? code}) => ItemLine(
  ReceiptLineItem(name: name, totalPriceCents: cents),
  rowNumber: row,
  code: code,
);

List<int> costs(ReceiptReconciliation r) => [
  for (final i in r.items) i.totalPriceCents,
];

void main() {
  group('allocate', () {
    test('shares in proportion, in whole cents that add up exactly', () {
      expect(ReceiptReconciler.allocate(23000, [100000, 10000, 5000]), [
        20000,
        2000,
        1000,
      ]);
    });

    test('the cents left over go to the largest, the first on a tie', () {
      expect(ReceiptReconciler.allocate(100, [300, 300, 300]), [34, 33, 33]);
      expect(ReceiptReconciler.allocate(5000, [31000, 45550, 23000]), [
        1557,
        2288,
        1155,
      ]);
    });

    test('a capped share is never more than its weight', () {
      expect(ReceiptReconciler.allocate(1000, [100, 200]), [100, 200]);
      expect(ReceiptReconciler.allocate(1000, [100, 200], capped: false), [
        333,
        667,
      ]);
    });

    test('nothing to share, or nothing to share it over, is all zeros', () {
      expect(ReceiptReconciler.allocate(0, [1, 2]), [0, 0]);
      expect(ReceiptReconciler.allocate(5, [0, 0]), [0, 0]);
    });
  });

  group('discounts', () {
    test('by code beat the item printed above', () {
      final result = ReceiptReconciler.reconcile(
        ReceiptBody(
          items: [
            item('SOAP', 35000, code: 'A'),
            item('PASTE', 36500, code: 'B'),
          ],
          discounts: const [DiscountLine(cents: 8800, code: 'A', belowItem: 1)],
          summaries: const [SummaryLine(LineRole.net, 62700)],
        ),
      );

      expect(costs(result), [26200, 36500]);
      expect(result.items.first.discountCents, 8800);
    });

    test('by row number only when listed under a heading', () {
      ReceiptReconciliation withListed({required bool listed}) =>
          ReceiptReconciler.reconcile(
            ReceiptBody(
              items: [item('A', 10000, row: 1), item('B', 10000, row: 2)],
              discounts: [
                DiscountLine(cents: 1000, rowNumber: 1, listed: listed),
              ],
            ),
          );

      expect(costs(withListed(listed: true)), [9000, 10000]);
      // Not listed and naming nothing else: the bill's.
      expect(costs(withListed(listed: false)), [9500, 9500]);
    });

    test('a discount larger than its item is the bill\'s', () {
      final result = ReceiptReconciler.reconcile(
        ReceiptBody(
          items: [item('A', 100000), item('B', 5000)],
          discounts: const [DiscountLine(cents: 10500, belowItem: 1)],
          summaries: const [SummaryLine(LineRole.total, 94500)],
        ),
      );

      expect(costs(result), [90000, 4500]);
    });
  });

  group('readings', () {
    test('the total is the strongest label, then the last printed', () {
      final result = ReceiptReconciler.reconcile(
        ReceiptBody(
          items: [item('A', 10000)],
          summaries: const [
            SummaryLine(LineRole.net, 10000),
            SummaryLine(LineRole.total, 99999),
          ],
        ),
      );

      expect(result.totalCents, 10000);
    });

    test('a total printed below the payment comes last', () {
      final result = ReceiptReconciler.reconcile(
        ReceiptBody(
          items: [item('A', 10000)],
          summaries: const [
            SummaryLine(LineRole.total, 12000, afterPayment: true),
            SummaryLine(LineRole.total, 99999),
          ],
        ),
      );

      // Neither adds up; the one above the payment is the answer.
      expect(result.totalCents, 99999);
    });

    test('a later total line is tried when the first does not add up', () {
      final result = ReceiptReconciler.reconcile(
        ReceiptBody(
          items: [item('A', 10000)],
          summaries: const [
            SummaryLine(LineRole.total, 10000),
            SummaryLine(LineRole.total, 12000),
          ],
        ),
      );

      expect(result.totalCents, 10000);
    });

    test('tax and service on top are spread; included tax is not', () {
      final onTop = ReceiptReconciler.reconcile(
        ReceiptBody(
          items: [item('A', 10000), item('B', 30000)],
          summaries: const [
            SummaryLine(LineRole.tax, 6000),
            SummaryLine(LineRole.service, 4000),
            SummaryLine(LineRole.total, 50000),
          ],
        ),
      );
      expect(costs(onTop), [12500, 37500]);
      expect(onTop.items.first.chargesCents, 2500);
      expect(onTop.taxCents, 6000);

      final included = ReceiptReconciler.reconcile(
        ReceiptBody(
          items: [item('A', 11500)],
          summaries: const [
            SummaryLine(LineRole.tax, 1500),
            SummaryLine(LineRole.total, 11500),
          ],
        ),
      );
      expect(included.items.single.chargesCents, 0);
    });

    test('a printed rounding accounts for its difference on the largest '
        'item', () {
      final result = ReceiptReconciler.reconcile(
        ReceiptBody(
          items: [item('A', 10025), item('B', 20000)],
          summaries: const [
            SummaryLine(LineRole.rounding, 25),
            SummaryLine(LineRole.total, 30000),
          ],
        ),
      );

      expect(costs(result), [10025, 19975]);
    });

    test('discounts already in the prices are not taken twice', () {
      final result = ReceiptReconciler.reconcile(
        ReceiptBody(
          items: [item('A', 9000)],
          discounts: const [DiscountLine(cents: 1000, belowItem: 0)],
          summaries: const [SummaryLine(LineRole.total, 9000)],
        ),
      );

      expect(costs(result), [9000]);
    });

    test('with no total line, the cash less the change, then the card, then '
        'the sub-total', () {
      ReceiptReconciliation of(List<SummaryLine> summaries) =>
          ReceiptReconciler.reconcile(
            ReceiptBody(items: [item('A', 10000)], summaries: summaries),
          );

      expect(
        of(const [
          SummaryLine(LineRole.gross, 10000),
          SummaryLine(LineRole.tender, 50000),
          SummaryLine(LineRole.change, 40000),
        ]).totalCents,
        10000,
      );
      expect(of(const [SummaryLine(LineRole.gross, 12000)]).totalGuessed, true);
      expect(
        of(const [
          SummaryLine(LineRole.gross, 12000),
          SummaryLine(LineRole.tender, 50000),
          SummaryLine(LineRole.change, 38000),
        ]).totalGuessed,
        isFalse,
        reason: 'two figures give 120.00',
      );
    });
  });
}
