import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/expense_photos.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/receipt_image_local_datasource.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/receipt_image_vault.dart';
import 'package:moneyora/features/receipt_scanner/data/repositories/expense_photos_impl.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';

void main() {
  late _FakeImages images;
  late _FakeVault vault;
  late ExpensePhotosImpl photos;

  setUp(() {
    images = _FakeImages();
    vault = _FakeVault();
    photos = ExpensePhotosImpl(images, vault);
  });

  group('pickAndKeep', () {
    test('keeps the picked photo in the vault and returns its path', () async {
      images.path = '/cache/picked.jpg';

      final result = await photos.pickAndKeep(PhotoSource.gallery);

      expect(result, const Right<Failure, String?>('/vault/kept.jpg.enc'));
      expect(images.askedFor, ReceiptImageSource.gallery);
      expect(vault.kept, '/cache/picked.jpg');
    });

    test('asks the camera for the camera', () async {
      await photos.pickAndKeep(PhotoSource.camera);

      expect(images.askedFor, ReceiptImageSource.camera);
    });

    test('backing out keeps nothing', () async {
      final result = await photos.pickAndKeep(PhotoSource.camera);

      expect(result, const Right<Failure, String?>(null));
      expect(vault.kept, isNull);
    });

    test('a refused permission becomes a PermissionFailure', () async {
      images.throwWith = const PermissionException('Allow the camera.');

      final result = await photos.pickAndKeep(PhotoSource.camera);

      expect(
        result,
        const Left<Failure, String?>(PermissionFailure('Allow the camera.')),
      );
    });

    test('a vault that cannot write becomes a CacheFailure', () async {
      images.path = '/cache/picked.jpg';
      vault.throwWith = const CacheException('disk full');

      final result = await photos.pickAndKeep(PhotoSource.gallery);

      expect(result, const Left<Failure, String?>(CacheFailure('disk full')));
    });
  });

  group('read', () {
    test('decrypts through the vault', () async {
      final result = await photos.read('/vault/a.enc');

      expect(result.getRight().toNullable(), [1, 2, 3]);
      expect(vault.readPath, '/vault/a.enc');
    });

    test('a file that will not unlock is an EncryptionFailure', () async {
      vault.throwWith = const EncryptionException('altered');

      final result = await photos.read('/vault/a.enc');

      expect(
        result,
        const Left<Failure, Uint8List?>(EncryptionFailure('altered')),
      );
    });
  });

  group('discard', () {
    test('deletes through the vault', () async {
      final result = await photos.discard('/vault/a.enc');

      expect(result, const Right<Failure, Unit>(unit));
      expect(vault.discarded, ['/vault/a.enc']);
    });

    test('a failed delete is a failure, not a throw', () async {
      vault.throwWith = const CacheException('locked');

      final result = await photos.discard('/vault/a.enc');

      expect(result, const Left<Failure, Unit>(CacheFailure('locked')));
    });
  });
}

class _FakeImages implements ReceiptImageLocalDataSource {
  String? path;
  AppException? throwWith;
  ReceiptImageSource? askedFor;

  @override
  Future<String?> pick(ReceiptImageSource source) async {
    askedFor = source;
    if (throwWith case final e?) throw e;
    return path;
  }
}

class _FakeVault implements ReceiptImageVault {
  AppException? throwWith;
  String? kept;
  String? readPath;
  final List<String> discarded = [];

  @override
  bool holds(String path) => path.endsWith('.enc');

  @override
  Future<String> keep(String sourcePath) async {
    if (throwWith case final e?) throw e;
    kept = sourcePath;
    return '/vault/kept.jpg.enc';
  }

  @override
  Future<Uint8List?> read(String path) async {
    if (throwWith case final e?) throw e;
    readPath = path;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> discard(String path) async {
    if (throwWith case final e?) throw e;
    discarded.add(path);
  }

  @override
  Future<T> withPlainCopy<T>(
    String path,
    Future<T> Function(String plainPath) body,
  ) => throw UnimplementedError('withPlainCopy');

  @override
  Future<String> keepBytes(Uint8List bytes, {required String extension}) =>
      throw UnimplementedError('keepBytes');
}
