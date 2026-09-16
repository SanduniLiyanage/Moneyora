@TestOn('vm')
library;

import 'dart:async';
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
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/scanned_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/keyword_dictionary_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/categorise_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parse_receipt_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/pick_receipt_image.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/read_receipt_image.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/scan_receipt.dart';
import 'package:moneyora/features/receipt_scanner/presentation/pages/scan_receipt_page.dart';
import 'package:moneyora/injection.dart';

/// The device, scripted: what the picker answers and what the recogniser
/// reads off the path it gave. The pipeline between them is real.
class _FakeDevice implements ReceiptRepository {
  Either<Failure, String?> picked = const Right('/cache/receipt.jpg');
  Either<Failure, RecognisedText> read = Right(
    RecognisedText.fromString(
      'KEELLS SUPER\nRICE 5KG 1,250.00\nTOTAL 1,250.00',
    ),
  );
  Completer<void>? hold;
  ReceiptImageSource? askedFor;
  String? scannedPath;

  @override
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source) async {
    askedFor = source;
    return picked;
  }

  @override
  Future<Either<Failure, String>> keepImage(String imagePath) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Uint8List?>> loadImage(String imagePath) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) async {
    scannedPath = imagePath;
    if (hold != null) await hold!.future;
    return read;
  }

  @override
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory() =>
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

void main() {
  late _FakeDevice device;

  setUp(() => device = _FakeDevice());

  Widget boot() => ProviderScope(
    overrides: [
      pickReceiptImageProvider.overrideWith(
        (ref) async => PickReceiptImage(device),
      ),
      readReceiptImageProvider.overrideWith(
        (ref) async => ReadReceiptImage(
          ScanReceipt(device),
          const ParseReceiptText(),
          CategoriseReceipt(_NoDictionary()),
        ),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: Routes.scanReceipt,
        routes: [
          GoRoute(
            path: Routes.scanReceipt,
            builder: (context, state) => const ScanReceiptPage(),
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
          GoRoute(
            path: Routes.receiptHistory,
            builder: (context, state) =>
                const Scaffold(body: Text('the history')),
          ),
        ],
      ),
    ),
  );

  Finder camera() => find.widgetWithText(FilledButton, 'Take a photo');
  Finder gallery() =>
      find.widgetWithText(OutlinedButton, 'Choose from gallery');

  testWidgets('offers the camera and the gallery, and says the photo stays '
      'on the phone', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    expect(find.text('Scan Receipt'), findsOneWidget);
    expect(camera(), findsOneWidget);
    expect(gallery(), findsOneWidget);
    expect(
      find.text('Read on this phone. The photo never leaves it.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the app bar opens the receipt history', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Receipt history'));
    await tester.pumpAndSettle();

    expect(find.text('the history'), findsOneWidget);
  });

  testWidgets('a photo taken is read and opened for review (FR-RCP-002, '
      'FR-RCP-004)', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await tester.tap(camera());
    await tester.pumpAndSettle();

    expect(device.askedFor, ReceiptImageSource.camera);
    expect(device.scannedPath, '/cache/receipt.jpg');
    expect(find.text('review /cache/receipt.jpg KEELLS SUPER'), findsOneWidget);
  });

  testWidgets('the gallery button asks the gallery', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await tester.tap(gallery());
    await tester.pumpAndSettle();

    expect(device.askedFor, ReceiptImageSource.gallery);
    expect(find.textContaining('review '), findsOneWidget);
  });

  testWidgets('while reading, both buttons wait', (tester) async {
    device.hold = Completer<void>();
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await tester.tap(camera());
    await tester.pump();

    expect(find.text('Reading the receipt…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(camera()).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(gallery()).onPressed, isNull);

    device.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('review '), findsOneWidget);
  });

  testWidgets('backing out of the picker shows nothing and reads nothing', (
    tester,
  ) async {
    device.picked = const Right(null);
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await tester.tap(camera());
    await tester.pumpAndSettle();

    expect(device.scannedPath, isNull);
    expect(find.text('Scan Receipt'), findsOneWidget);
    expect(tester.widget<FilledButton>(camera()).onPressed, isNotNull);
    expect(find.textContaining('Could not'), findsNothing);
  });

  testWidgets('a refused permission is said in full, with the buttons '
      'still there', (tester) async {
    device.picked = const Left(
      PermissionFailure('Moneyora needs the camera to scan a receipt.'),
    );
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await tester.tap(camera());
    await tester.pumpAndSettle();

    expect(
      find.text('Moneyora needs the camera to scan a receipt.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(camera()).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(gallery()).onPressed, isNotNull);
  });

  testWidgets('a photo that cannot be read says so and allows another go', (
    tester,
  ) async {
    device.read = const Left(OcrFailure('No text was found on that image.'));
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await tester.tap(gallery());
    await tester.pumpAndSettle();

    expect(find.text('No text was found on that image.'), findsOneWidget);
    expect(find.textContaining('review '), findsNothing);

    // The next attempt clears the message while it runs.
    device.read = Right(
      RecognisedText.fromString('SHOP\nMILK 450.00\nTOTAL 450.00'),
    );
    await tester.tap(gallery());
    await tester.pumpAndSettle();
    expect(find.text('review /cache/receipt.jpg SHOP'), findsOneWidget);
  });
}
