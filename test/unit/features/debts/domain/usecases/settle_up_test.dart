import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/debts/domain/entities/debt_person.dart';
import 'package:moneyora/features/debts/domain/repositories/debt_repository.dart';
import 'package:moneyora/features/debts/domain/usecases/settle_up.dart';

class _Batches implements DebtRepository {
  final List<({List<Debt> add, List<Debt> update, List<int> delete})> batches =
      [];

  @override
  Future<Either<Failure, List<int>>> batch({
    List<Debt> add = const [],
    List<Debt> update = const [],
    List<int> delete = const [],
  }) async {
    batches.add((add: add, update: update, delete: delete));
    return Right([for (var i = 0; i < add.length; i++) 900 + i]);
  }

  @override
  Stream<Either<Failure, List<Debt>>> watch() => const Stream.empty();

  @override
  Future<Either<Failure, int>> add(Debt debt) => throw UnimplementedError();

  @override
  Future<Either<Failure, List<int>>> addAll(List<Debt> debts) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> update(Debt debt) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAll(List<Debt> debts) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> delete(int id) => throw UnimplementedError();
}

/// Settling up with a person, and taking it back. FR-DBT-007, E-47.
void main() {
  late _Batches repository;
  final on = DateTime(2026, 10, 20);

  setUp(() => repository = _Batches());

  Debt debt(
    int id,
    DebtDirection direction,
    int cents, {
    DateTime? paid,
    DateTime? since,
  }) => Debt(
    id: id,
    direction: direction,
    person: 'Nimal',
    amountCents: cents,
    incurredOn: since ?? DateTime(2026, 10, 1),
    paidOn: paid,
  );

  DebtPerson nimal(List<Debt> records) =>
      DebtPerson(name: 'Nimal', records: records);

  test('the net changes hands as a payment, and every open record closes', () {
    // Nimal owes Rs1,000 and is owed Rs400: he pays Rs600.
    final person = nimal([
      debt(1, DebtDirection.owedToMe, 100000),
      debt(2, DebtDirection.iOwe, 40000),
      debt(3, DebtDirection.owedToMe, 5000, paid: DateTime(2026, 10, 3)),
    ]);

    return SettleUp(repository)(Settlement(person, on: on)).then((result) {
      final settled = result.getOrElse((f) => throw StateError(f.message));
      final write = repository.batches.single;

      final payment = write.add.single;
      expect(payment.isPayment, isTrue);
      expect(payment.direction, DebtDirection.iOwe);
      expect(payment.amountCents, 60000);
      expect(payment.person, 'Nimal');
      expect(payment.incurredOn, on);
      expect(payment.paidOn, on, reason: 'closed with the rest');
      expect(payment.note, SettleUp.paymentNote);

      // The two open records, paid on the day; the paid one left alone.
      expect(
        [for (final d in write.update) (d.id, d.paidOn)],
        [(1, on), (2, on)],
      );
      expect(write.delete, isEmpty);
      expect(settled.paymentId, 900);
      expect([for (final d in settled.reopen) d.id], [1, 2]);
    });
  });

  test('owing them, the user pays the net', () async {
    await SettleUp(repository)(
      Settlement(
        nimal([
          debt(1, DebtDirection.owedToMe, 10000),
          debt(2, DebtDirection.iOwe, 35000),
        ]),
        on: on,
      ),
    );

    final payment = repository.batches.single.add.single;
    expect(payment.direction, DebtDirection.owedToMe);
    expect(payment.amountCents, 25000);
  });

  test('square, nothing changes hands and no payment is written', () async {
    final result = await SettleUp(repository)(
      Settlement(
        nimal([
          debt(1, DebtDirection.owedToMe, 40000),
          debt(2, DebtDirection.iOwe, 40000),
        ]),
        on: on,
      ),
    );

    expect(repository.batches.single.add, isEmpty);
    expect(repository.batches.single.update, hasLength(2));
    expect(
      result.getOrElse((f) => throw StateError(f.message)).paymentId,
      isNull,
    );
  });

  group('refused, before anything is written', () {
    Future<void> refused(Settlement settlement, String message) async {
      final result = await SettleUp(repository)(settlement);
      expect(result.match((f) => f.message, (_) => 'written'), message);
      expect(repository.batches, isEmpty);
    }

    test(
      'nothing open',
      () => refused(
        Settlement(
          nimal([
            debt(1, DebtDirection.owedToMe, 100, paid: DateTime(2026, 10, 2)),
          ]),
          on: on,
        ),
        'Nothing is open with them.',
      ),
    );

    test(
      'a day in the future',
      () => refused(
        Settlement(
          nimal([debt(1, DebtDirection.owedToMe, 100)]),
          on: DateTime.now().add(const Duration(days: 2)),
        ),
        'It cannot be settled in the future.',
      ),
    );

    test(
      'a day before a record began',
      () => refused(
        Settlement(
          nimal([
            debt(1, DebtDirection.owedToMe, 100),
            debt(2, DebtDirection.iOwe, 100, since: DateTime(2026, 10, 15)),
          ]),
          on: DateTime(2026, 10, 10),
        ),
        'It cannot be settled before the latest of these began.',
      ),
    );
  });

  test(
    'undo opens the records as they were and takes the payment away',
    () async {
      final before = [
        debt(1, DebtDirection.owedToMe, 100000),
        debt(2, DebtDirection.iOwe, 40000),
      ];

      await UndoSettleUp(repository)(Settled(reopen: before, paymentId: 900));

      final write = repository.batches.single;
      expect(write.update, before);
      expect(write.delete, [900]);
      expect(write.add, isEmpty);
    },
  );

  test('undo of a square settlement deletes nothing', () async {
    await UndoSettleUp(repository)(
      Settled(reopen: [debt(1, DebtDirection.owedToMe, 100)]),
    );

    expect(repository.batches.single.delete, isEmpty);
  });
}
