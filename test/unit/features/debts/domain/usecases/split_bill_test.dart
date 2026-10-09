import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/debts/domain/repositories/debt_repository.dart';
import 'package:moneyora/features/debts/domain/usecases/split_bill.dart';

/// Records the debts it was asked to write together.
class _FakeRepository implements DebtRepository {
  List<Debt>? written;

  @override
  Future<Either<Failure, List<int>>> addAll(List<Debt> debts) async {
    written = debts;
    return Right([for (var i = 0; i < debts.length; i++) i + 1]);
  }

  @override
  Future<Either<Failure, int>> add(Debt debt) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> update(Debt debt) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> delete(int id) => throw UnimplementedError();

  @override
  Stream<Either<Failure, List<Debt>>> watch() => throw UnimplementedError();
}

/// A bill split evenly, and the debts it leaves. FR-DBT-004, E-44.
void main() {
  final on = DateTime(2026, 10, 8);

  SplitRequest request({
    int total = 300000,
    List<String> others = const ['Nimal', 'Saman'],
    int? paidBy,
    String? note = 'Dinner',
  }) => SplitRequest(
    totalCents: total,
    others: others,
    paidBy: paidBy,
    on: on,
    note: note,
  );

  group('shares', () {
    test('divide evenly when they can', () {
      expect(SplitBill.shares(300000, 3), [100000, 100000, 100000]);
    });

    test('give the cents that do not divide to the first people, one each, '
        'and add up to the bill', () {
      final shares = SplitBill.shares(100000, 3);

      expect(shares, [33334, 33333, 33333]);
      expect(shares.reduce((a, b) => a + b), 100000);
      expect(SplitBill.shares(1001, 4), [251, 250, 250, 250]);
    });
  });

  group('the debts', () {
    test('the user paid: each of the others owes the user their share', () {
      final debts = SplitBill.debtsFor(request(total: 100000));

      expect(debts.map((d) => (d.person, d.direction, d.amountCents)), [
        ('Nimal', DebtDirection.owedToMe, 33333),
        ('Saman', DebtDirection.owedToMe, 33333),
      ]);
      expect(debts.first.note, 'Dinner, split 3 ways');
      expect(debts.first.incurredOn, on);
    });

    test('someone else paid: the user owes them their own share', () {
      final debts = SplitBill.debtsFor(request(total: 100000, paidBy: 1));

      expect(debts.single.person, 'Saman');
      expect(debts.single.direction, DebtDirection.iOwe);
      // The user is first, so the user's share takes the odd cent.
      expect(debts.single.amountCents, 33334);
    });

    test('with nothing said, the note still says what it was', () {
      expect(
        SplitBill.debtsFor(request(note: '  ')).first.note,
        'A bill, split 3 ways',
      );
    });

    test('are written together', () async {
      final repository = _FakeRepository();

      final result = await SplitBill(repository)(request());

      expect(result.getRight().toNullable(), [1, 2]);
      expect(repository.written, hasLength(2));
    });
  });

  group('refuses', () {
    test('no total', () {
      expect(SplitBill.validate(request(total: 0))?.field, 'total');
    });

    test('no one to split with, or a person with no name', () {
      expect(SplitBill.validate(request(others: const []))?.field, 'people');
      expect(
        SplitBill.validate(request(others: const ['Nimal', ' ']))?.field,
        'people',
      );
    });

    test('more people than the limit', () {
      expect(
        SplitBill.validate(
          request(others: [for (var i = 0; i < 20; i++) 'P$i']),
        )?.field,
        'people',
      );
      expect(
        SplitBill.validate(
          request(others: [for (var i = 0; i < 19; i++) 'P$i']),
        ),
        isNull,
      );
    });

    test('a payer who is not in the list', () {
      expect(SplitBill.validate(request(paidBy: 2))?.field, 'paidBy');
    });

    test('and writes nothing when it refuses', () async {
      final repository = _FakeRepository();

      final result = await SplitBill(repository)(request(total: 0));

      expect(result.isLeft(), isTrue);
      expect(repository.written, isNull);
    });
  });
}
