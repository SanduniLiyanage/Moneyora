@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/keyword_match.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/scanned_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/keyword_dictionary_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/categorise_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/get_scan_history.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/load_receipt_image.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parse_receipt_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/read_receipt_image.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/scan_receipt.dart';
import 'package:moneyora/features/receipt_scanner/presentation/pages/receipt_history_page.dart';
import 'package:moneyora/injection.dart';

/// The history over the real use cases and a scripted repository: the
/// search is `GetScanHistory`'s, so what the screen shows for "keells"
/// is what the use case returns for it; a re-scan runs the real pipeline
/// over what the recogniser is scripted to read. The picker is never
/// asked — FR-RCP-014 starts past it.
class _FakeReceipts implements ReceiptRepository {
  _FakeReceipts(this.history);

  Either<Failure, List<ReceiptScan>> history;
  Either<Failure, RecognisedText> read = Right(
    RecognisedText.fromString(
      'KEELLS SUPER\nRICE 5KG 1,250.00\nTOTAL 1,250.00',
    ),
  );
  Completer<void>? hold;
  String? scannedPath;

  @override
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory() async => history;

  @override
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source) =>
      throw UnimplementedError();

  Either<Failure, Uint8List?> image = const Right(null);
  String? imageAskedFor;

  @override
  Future<Either<Failure, String>> keepImage(String imagePath) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Uint8List?>> loadImage(String imagePath) async {
    imageAskedFor = imagePath;
    return image;
  }

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) async {
    scannedPath = imagePath;
    if (hold != null) await hold!.future;
    return read;
  }

  @override
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan) =>
      throw UnimplementedError();
}

class _NoDictionary implements KeywordDictionaryRepository {
  @override
  Future<Either<Failure, List<KeywordMatch>>> matchesFor(String text) async =>
      const Right([]);

  @override
  Future<Either<Failure, Unit>> learn({
    required String text,
    required int categoryId,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> recordApplied({
    required String text,
    required int categoryId,
  }) => throw UnimplementedError();
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

/// A one-pixel PNG: enough for `Image.memory` to build over, and nothing
/// here asserts on pixels.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB'
    '0C8AAAAASUVORK5CYII=',
  ),
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
      readReceiptImageProvider.overrideWith(
        (ref) async => ReadReceiptImage(
          ScanReceipt(receipts),
          const ParseReceiptText(),
          CategoriseReceipt(_NoDictionary()),
        ),
      ),
      loadReceiptImageProvider.overrideWith(
        (ref) async => LoadReceiptImage(receipts),
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
          GoRoute(
            path: Routes.scanReceiptReview,
            builder: (context, state) => Scaffold(
              body: Text(
                'review ${(state.extra! as ScannedReceipt).imagePath} '
                '${(state.extra! as ScannedReceipt).receipt.receipt.merchantName}',
              ),
            ),
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

    testWidgets('on a narrow phone the store name keeps one line, with the '
        'total under the date and the button beside', (tester) async {
      // 320 logical pixels: the emulator width that wrapped "La Viventey"
      // one syllable per line while the total sat in the trailing slot.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(boot(_FakeReceipts(Right([_keells]))));
      await tester.pumpAndSettle();

      final title = tester.getRect(find.text('KEELLS SUPER'));
      final date = tester.getRect(find.text('Sep 12, 2026 · 2 items'));
      final total = tester.getRect(find.text('Rs1,900.00'));
      final button = tester.getRect(find.byType(IconButton));
      expect(title.height, lessThanOrEqualTo(date.height + 4)); // one line
      expect(date.top, greaterThanOrEqualTo(title.bottom));
      expect(total.top, greaterThanOrEqualTo(date.bottom));
      expect(total.left, title.left);
      expect(title.right, lessThanOrEqualTo(button.left));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a receipt with no store, printed date or total is placed '
        'by when it was scanned', (tester) async {
      await tester.pumpWidget(boot(_FakeReceipts(Right([_bare]))));
      await tester.pumpAndSettle();

      expect(find.text('Unknown store'), findsOneWidget);
      expect(find.text('Scanned Sep 1, 2026 · 1 item'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('a photo that is gone shows a placeholder, not an error', (
      tester,
    ) async {
      final receipts = _FakeReceipts(Right([_keells]));
      await tester.pumpWidget(boot(receipts));
      await tester.pumpAndSettle();

      expect(receipts.imageAskedFor, '/no/such/keells.jpg');
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a kept photo is drawn from the bytes the repository '
        'unlocks (FR-RCP-012)', (tester) async {
      final receipts = _FakeReceipts(Right([_keells]))..image = Right(_png);
      await tester.pumpWidget(boot(receipts));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
    });

    testWidgets('a photo that will not unlock shows a lock, and the row '
        'still stands', (tester) async {
      final receipts = _FakeReceipts(Right([_keells]))
        ..image = const Left(EncryptionFailure('altered'));
      await tester.pumpWidget(boot(receipts));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('KEELLS SUPER'), findsOneWidget);
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

  group('the viewer', () {
    testWidgets('opens the photo from the bytes the repository unlocks', (
      tester,
    ) async {
      final receipts = _FakeReceipts(Right([_keells]))..image = Right(_png);
      await tester.pumpWidget(boot(receipts));
      await tester.pumpAndSettle();

      await tester.tap(find.text('KEELLS SUPER'));
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptHistoryPage), findsNothing);
      expect(find.text('KEELLS SUPER'), findsOneWidget); // the app bar
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('says when the photo is gone', (tester) async {
      await tester.pumpWidget(boot(_FakeReceipts(Right([_keells]))));
      await tester.pumpAndSettle();

      await tester.tap(find.text('KEELLS SUPER'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsNothing);
      expect(
        find.text('The photo is no longer on this phone.'),
        findsOneWidget,
      );
    });

    testWidgets('says why a photo would not unlock, in the failure\'s '
        'words', (tester) async {
      final receipts = _FakeReceipts(Right([_keells]))
        ..image = const Left(
          EncryptionFailure('The receipt photo could not be unlocked.'),
        );
      await tester.pumpWidget(boot(receipts));
      await tester.pumpAndSettle();

      await tester.tap(find.text('KEELLS SUPER'));
      await tester.pumpAndSettle();

      expect(
        find.text('The receipt photo could not be unlocked.'),
        findsOneWidget,
      );
    });
  });

  group('re-scan (FR-RCP-014)', () {
    // The row checks the disk before the recogniser is asked, so the
    // photo that is "kept" has to be a real file.
    late Directory dir;
    late ReceiptScan kept;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('moneyora_rescan');
      final file = File('${dir.path}${Platform.pathSeparator}keells.jpg')
        ..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
      kept = ReceiptScan(
        id: 4,
        scannedAt: DateTime(2026, 9, 14),
        imagePath: file.path,
        status: ReceiptScanStatus.confirmed,
        merchantName: 'KEELLS SUPER',
        totalCents: 125000,
      );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Finder rescan() =>
        find.widgetWithIcon(IconButton, Icons.document_scanner_outlined);

    testWidgets('reads the kept photo again, past the picker, and opens '
        'the review on it', (tester) async {
      final receipts = _FakeReceipts(Right([kept]));
      await tester.pumpWidget(boot(receipts));
      await tester.pumpAndSettle();

      await tester.tap(rescan());
      await tester.pumpAndSettle();

      expect(receipts.scannedPath, kept.imagePath);
      expect(
        find.text('review ${kept.imagePath} KEELLS SUPER'),
        findsOneWidget,
      );
    });

    testWidgets('while reading, every row waits', (tester) async {
      final receipts = _FakeReceipts(Right([kept, _keells]))
        ..hold = Completer<void>();
      await tester.pumpWidget(boot(receipts));
      await tester.pumpAndSettle();

      await tester.tap(rescan().first);
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      for (final button in tester.widgetList<IconButton>(rescan())) {
        expect(button.onPressed, isNull);
      }

      receipts.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('review '), findsOneWidget);
    });

    testWidgets('a photo no longer on disk is said so, and nothing is '
        'read', (tester) async {
      final receipts = _FakeReceipts(Right([_keells]));
      await tester.pumpWidget(boot(receipts));
      await tester.pumpAndSettle();

      await tester.tap(rescan());
      await tester.pumpAndSettle();

      expect(receipts.scannedPath, isNull);
      expect(
        find.text('The photo is no longer on this phone.'),
        findsOneWidget,
      );
      expect(find.byType(ReceiptHistoryPage), findsOneWidget);
      expect(tester.widget<IconButton>(rescan()).onPressed, isNotNull);
    });

    testWidgets('a photo that cannot be read says so over the list, and '
        'allows another go', (tester) async {
      final receipts = _FakeReceipts(Right([kept]))
        ..read = const Left(OcrFailure('No text was found on that image.'));
      await tester.pumpWidget(boot(receipts));
      await tester.pumpAndSettle();

      await tester.tap(rescan());
      await tester.pumpAndSettle();

      expect(find.text('No text was found on that image.'), findsOneWidget);
      expect(find.byType(ReceiptHistoryPage), findsOneWidget);
      expect(find.textContaining('review '), findsNothing);

      receipts.read = Right(
        RecognisedText.fromString('SHOP\nMILK 450.00\nTOTAL 450.00'),
      );
      await tester.tap(rescan());
      await tester.pumpAndSettle();
      expect(find.text('review ${kept.imagePath} SHOP'), findsOneWidget);
    });
  });
}
