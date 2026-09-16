@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/get_scan_history.dart';
import 'package:moneyora/features/receipt_scanner/presentation/pages/receipt_history_page.dart';
import 'package:moneyora/injection.dart';

/// The history over the real use case and a scripted repository: the
/// search is `GetScanHistory`'s, so what the screen shows for "keells"
/// is what the use case returns for it.
class _FakeReceipts implements ReceiptRepository {
  _FakeReceipts(this.history);

  Either<Failure, List<ReceiptScan>> history;

  @override
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory() async => history;

  @override
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan) =>
      throw UnimplementedError();
}

final _keells = ReceiptScan(
  id: 2,
  scannedAt: DateTime(2026, 9, 14, 18, 30),
  imagePath: '/no/such/keells.jpg',
  status: ReceiptScanStatus.confirmed,
  merchantName: 'KEELLS SUPER',
  receiptDate: DateTime(2026, 9, 12, 14, 5),
  receiptNumber: '4521',
  totalCents: 190000,
  items: const [
    ReceiptScanItem(
      item: ReceiptLineItem(name: 'RICE 5KG', totalPriceCents: 125000),
      confidence: 90,
    ),
    ReceiptScanItem(
      item: ReceiptLineItem(name: 'PANADOL', totalPriceCents: 12000),
      confidence: 20,
    ),
  ],
);

/// A receipt the parser read almost nothing off: no store, no printed
/// date, no total — the list still has to place it.
final _bare = ReceiptScan(
  id: 1,
  scannedAt: DateTime(2026, 9, 1, 9),
  imagePath: '/no/such/bare.jpg',
  status: ReceiptScanStatus.confirmed,
  items: const [
    ReceiptScanItem(
      item: ReceiptLineItem(name: 'Bread', totalPriceCents: 45000),
      confidence: 80,
    ),
  ],
);

final _pending = ReceiptScan(
  id: 3,
  scannedAt: DateTime(2026, 9, 15),
  imagePath: '/no/such/pending.jpg',
  status: ReceiptScanStatus.pending,
  merchantName: 'Arpico',
  totalCents: 5000,
);

void main() {
  Widget boot(_FakeReceipts receipts) => ProviderScope(
    overrides: [
      getScanHistoryProvider.overrideWith(
        (ref) async => GetScanHistory(receipts),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: Routes.receiptHistory,
        routes: [
          GoRoute(
            path: Routes.receiptHistory,
            builder: (context, state) => const ReceiptHistoryPage(),
          ),
          GoRoute(
            path: Routes.scanReceipt,
            builder: (context, state) =>
                const Scaffold(body: Text('the scanner')),
          ),
        ],
      ),
    ),
  );

  group('the list', () {
    testWidgets('shows every receipt with its store, date, item count and '
        'total, in the order given', (tester) async {
      await tester.pumpWidget(boot(_FakeReceipts(Right([_keells, _bare]))));
      await tester.pumpAndSettle();

      expect(find.text('Receipt history'), findsOneWidget);
      expect(find.text('KEELLS SUPER'), findsOneWidget);
      expect(find.text('Sep 12, 2026 · 2 items'), findsOneWidget);
      expect(find.text('Rs1,900.00'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('KEELLS SUPER')).dy,
        lessThan(tester.getTopLeft(find.text('Unknown store')).dy),
      );
    });

    testWidgets('a receipt with no store, printed date or total is placed '
        'by when it was scanned', (tester) async {
      await tester.pumpWidget(boot(_FakeReceipts(Right([_bare]))));
      await tester.pumpAndSettle();

      expect(find.text('Unknown store'), findsOneWidget);
      expect(find.text('Scanned Sep 1, 2026 · 1 item'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('a photo no longer on disk shows a placeholder, not an '
        'error', (tester) async {
      await tester.pumpWidget(boot(_FakeReceipts(Right([_keells]))));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a scan not in the ledger says so; a confirmed one says '
        'nothing', (tester) async {
      await tester.pumpWidget(boot(_FakeReceipts(Right([_pending, _keells]))));
      await tester.pumpAndSettle();

      expect(find.textContaining('not confirmed'), findsOneWidget);
      expect(
        find.text('Scanned Sep 15, 2026 · 0 items · not confirmed'),
        findsOneWidget,
      );
    });

    testWidgets('with no receipts, says so and offers the scanner', (
      tester,
    ) async {
      await tester.pumpWidget(boot(_FakeReceipts(const Right([]))));
      await tester.pumpAndSettle();

      expect(find.text('No receipts yet'), findsOneWidget);
      await tester.tap(find.text('Scan a receipt'));
      await tester.pumpAndSettle();
      expect(find.text('the scanner'), findsOneWidget);
    });

    testWidgets('a failure reading shows its message', (tester) async {
      await tester.pumpWidget(
        boot(_FakeReceipts(const Left(CacheFailure('disk is full')))),
      );
      await tester.pumpAndSettle();

      expect(find.text('disk is full'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('narrows the list by what is typed, and clearing restores '
        'it', (tester) async {
      await tester.pumpWidget(boot(_FakeReceipts(Right([_keells, _bare]))));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'bread');
      await tester.pumpAndSettle();
      expect(find.text('Unknown store'), findsOneWidget);
      expect(find.text('KEELLS SUPER'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('KEELLS SUPER'), findsOneWidget);
      expect(find.text('Unknown store'), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsNothing);
    });

    testWidgets('finds a receipt by its printed number', (tester) async {
      await tester.pumpWidget(boot(_FakeReceipts(Right([_keells, _bare]))));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '4521');
      await tester.pumpAndSettle();

      expect(find.text('KEELLS SUPER'), findsOneWidget);
      expect(find.text('Unknown store'), findsNothing);
    });

    testWidgets('nothing matching says what was searched for, not "no '
        'receipts"', (tester) async {
      await tester.pumpWidget(boot(_FakeReceipts(Right([_keells, _bare]))));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'cargills ');
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches "cargills".'), findsOneWidget);
      expect(find.text('No receipts yet'), findsNothing);
    });
  });

  testWidgets('tapping a receipt opens its photo, or says it is gone', (
    tester,
  ) async {
    await tester.pumpWidget(boot(_FakeReceipts(Right([_keells]))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('KEELLS SUPER'));
    await tester.pumpAndSettle();

    expect(find.byType(ReceiptHistoryPage), findsNothing);
    expect(find.text('KEELLS SUPER'), findsOneWidget); // the app bar
    expect(find.text('The photo is no longer on this phone.'), findsOneWidget);
  });
}
