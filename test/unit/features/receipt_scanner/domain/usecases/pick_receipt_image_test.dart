import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/pick_receipt_image.dart';

class _FakeRepository implements ReceiptRepository {
  Either<Failure, String?> answer = const Right(null);
  ReceiptImageSource? askedFor;

  @override
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source) async {
    askedFor = source;
    return answer;
  }

  @override
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory() =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) =>
      throw UnimplementedError();
}

void main() {
  late _FakeRepository repository;
  late PickReceiptImage pick;

  setUp(() {
    repository = _FakeRepository();
    pick = PickReceiptImage(repository);
  });

  test('passes the source through and returns the path', () async {
    repository.answer = const Right('/cache/receipt.jpg');

    final result = await pick(ReceiptImageSource.camera);

    expect(result, const Right<Failure, String?>('/cache/receipt.jpg'));
    expect(repository.askedFor, ReceiptImageSource.camera);
  });

  test('a cancelled pick comes back as Right(null)', () async {
    expect(
      await pick(ReceiptImageSource.gallery),
      const Right<Failure, String?>(null),
    );
  });

  test('a refusal comes back as the repository said it', () async {
    repository.answer = const Left(PermissionFailure('no camera for you'));

    expect(
      await pick(ReceiptImageSource.camera),
      const Left<Failure, String?>(PermissionFailure('no camera for you')),
    );
  });
}
