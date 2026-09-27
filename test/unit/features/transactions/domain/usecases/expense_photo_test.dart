import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/expense_photos.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/usecases/attach_expense_photo.dart';
import 'package:moneyora/features/transactions/domain/usecases/discard_unused_photos.dart';
import 'package:moneyora/features/transactions/domain/usecases/load_expense_photo.dart';

void main() {
  late _FakePhotos photos;

  setUp(() => photos = _FakePhotos());

  Transaction expense({String? photo, int? scanId}) => Transaction(
    id: 1,
    accountId: 1,
    categoryId: 1,
    amountCents: 1000,
    type: TransactionType.expense,
    date: DateTime(2026, 9, 27),
    receiptImagePath: photo,
    receiptScanId: scanId,
  );

  group('Transaction.attachedPhotoPath', () {
    test('is the photo of a row entered by hand', () {
      expect(expense(photo: 'a.jpg').attachedPhotoPath, 'a.jpg');
    });

    test('is never a scan photo, which the scan record owns', () {
      expect(expense(photo: 'a.jpg', scanId: 4).attachedPhotoPath, isNull);
    });

    test('is null with no photo', () {
      expect(expense().attachedPhotoPath, isNull);
    });
  });

  group('AttachExpensePhoto', () {
    test('hands back the kept path for the source asked for', () async {
      photos.nextPick = const Right('kept.jpg');

      final result = await AttachExpensePhoto(photos)(PhotoSource.camera);

      expect(result, const Right<Failure, String?>('kept.jpg'));
      expect(photos.pickedFrom, [PhotoSource.camera]);
    });

    test('backing out is not a failure', () async {
      photos.nextPick = const Right(null);

      final result = await AttachExpensePhoto(photos)(PhotoSource.gallery);

      expect(result, const Right<Failure, String?>(null));
    });

    test('a refused permission comes through in its own words', () async {
      photos.nextPick = const Left(PermissionFailure('Allow the camera.'));

      final result = await AttachExpensePhoto(photos)(PhotoSource.camera);

      expect(result.getLeft().toNullable()?.message, 'Allow the camera.');
    });
  });

  group('LoadExpensePhoto', () {
    test('reads the bytes at the path', () async {
      photos.stored['a.jpg'] = Uint8List.fromList([1, 2, 3]);

      final result = await LoadExpensePhoto(photos)('a.jpg');

      expect(result.getRight().toNullable(), [1, 2, 3]);
    });

    test('a blank path is no photo, without asking the vault', () async {
      final result = await LoadExpensePhoto(photos)('  ');

      expect(result, const Right<Failure, Uint8List?>(null));
      expect(photos.readPaths, isEmpty);
    });
  });

  group('DiscardUnusedPhotos.unused', () {
    test('a photo kept and saved stays', () {
      expect(
        DiscardUnusedPhotos.unused(
          PhotoCleanup(
            after: expense(photo: 'new.jpg'),
            keptHere: const {'new.jpg'},
          ),
        ),
        isEmpty,
      );
    });

    test('photos kept and then replaced go', () {
      expect(
        DiscardUnusedPhotos.unused(
          PhotoCleanup(
            after: expense(photo: 'b.jpg'),
            keptHere: const {'a.jpg', 'b.jpg'},
          ),
        ),
        {'a.jpg'},
      );
    });

    test('a form abandoned gives back everything it kept', () {
      expect(
        DiscardUnusedPhotos.unused(
          const PhotoCleanup(keptHere: {'a.jpg', 'b.jpg'}),
        ),
        {'a.jpg', 'b.jpg'},
      );
    });

    test('the old photo goes when an edit replaces or removes it', () {
      expect(
        DiscardUnusedPhotos.unused(
          PhotoCleanup(
            before: expense(photo: 'old.jpg'),
            after: expense(photo: 'new.jpg'),
            keptHere: const {'new.jpg'},
          ),
        ),
        {'old.jpg'},
      );
      expect(
        DiscardUnusedPhotos.unused(
          PhotoCleanup(
            before: expense(photo: 'old.jpg'),
            after: expense(),
          ),
        ),
        {'old.jpg'},
      );
    });

    test('an edit that keeps the photo keeps it', () {
      expect(
        DiscardUnusedPhotos.unused(
          PhotoCleanup(
            before: expense(photo: 'old.jpg'),
            after: expense(photo: 'old.jpg'),
          ),
        ),
        isEmpty,
      );
    });

    test('a deleted row takes its own photo with it', () {
      expect(
        DiscardUnusedPhotos.unused(
          PhotoCleanup(before: expense(photo: 'old.jpg')),
        ),
        {'old.jpg'},
      );
    });

    test('never a scan photo, even from a deleted row', () {
      expect(
        DiscardUnusedPhotos.unused(
          PhotoCleanup(before: expense(photo: 'scan.jpg', scanId: 3)),
        ),
        isEmpty,
      );
    });
  });

  group('DiscardUnusedPhotos', () {
    test('discards each unused photo', () async {
      final result = await DiscardUnusedPhotos(photos)(
        PhotoCleanup(
          before: expense(photo: 'old.jpg'),
          keptHere: const {'a.jpg'},
        ),
      );

      expect(result, const Right<Failure, Unit>(unit));
      expect(photos.discarded, unorderedEquals(['old.jpg', 'a.jpg']));
    });

    test('tries every file and reports the first failure', () async {
      photos.failDiscard = {'a.jpg'};

      final result = await DiscardUnusedPhotos(photos)(
        const PhotoCleanup(keptHere: {'a.jpg', 'b.jpg'}),
      );

      expect(result.isLeft(), isTrue);
      expect(photos.discarded, ['b.jpg']);
    });

    test('with nothing unused, asks the vault for nothing', () async {
      final result = await DiscardUnusedPhotos(photos)(
        PhotoCleanup(
          after: expense(photo: 'a.jpg'),
          keptHere: const {'a.jpg'},
        ),
      );

      expect(result, const Right<Failure, Unit>(unit));
      expect(photos.discarded, isEmpty);
    });
  });
}

class _FakePhotos implements ExpensePhotos {
  Either<Failure, String?> nextPick = const Right(null);
  final List<PhotoSource> pickedFrom = [];
  final Map<String, Uint8List> stored = {};
  final List<String> readPaths = [];
  final List<String> discarded = [];
  Set<String> failDiscard = {};

  @override
  Future<Either<Failure, String?>> pickAndKeep(PhotoSource source) async {
    pickedFrom.add(source);
    return nextPick;
  }

  @override
  Future<Either<Failure, Uint8List?>> read(String path) async {
    readPaths.add(path);
    return Right(stored[path]);
  }

  @override
  Future<Either<Failure, Unit>> discard(String path) async {
    if (failDiscard.contains(path)) return const Left(CacheFailure());
    discarded.add(path);
    return const Right(unit);
  }
}
