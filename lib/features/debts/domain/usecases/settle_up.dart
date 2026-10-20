import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/debt.dart';
import '../entities/debt_person.dart';
import '../repositories/debt_repository.dart';

/// [person], settled up [on] a day. Input to [SettleUp].
class Settlement extends Equatable {
  /// Creates the request.
  const Settlement(this.person, {required this.on});

  /// The person, every record included.
  final DebtPerson person;

  /// The day it was settled.
  final DateTime on;

  @override
  List<Object?> get props => [person, on];
}

/// What [SettleUp] wrote, for [UndoSettleUp] to take back.
class Settled extends Equatable {
  /// Creates the record of a settlement.
  const Settled({required this.reopen, this.paymentId});

  /// The person's open records as they were before: what Undo puts back.
  final List<Debt> reopen;

  /// The payment written for the net, or null when the two were square.
  final int? paymentId;

  @override
  List<Object?> get props => [reopen, paymentId];
}

/// Settles up with a person: every open record marked paid on one day,
/// and what they owed each other on balance recorded as having changed
/// hands. FR-DBT-007, E-47.
///
/// The net changes hands, not each record: Nimal owing Rs1,000 and owed
/// Rs400 settles with Rs600 from Nimal. That amount is written as a
/// payment (FR-DBT-008) on the day, closed with the rest, so the history
/// says what moved. Square, nothing moves and no payment is written. All
/// of it is one write: a person half settled has a net that no longer
/// adds up.
class SettleUp implements UseCase<Settled, Settlement> {
  /// Creates the use case.
  const SettleUp(this._repository);

  final DebtRepository _repository;

  /// What the payment that settles up says it was.
  static const String paymentNote = 'Settled up';

  @override
  Future<Either<Failure, Settled>> call(Settlement params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);
    final open = params.person.open;
    final payment = paymentFor(params);
    final written = await _repository.batch(
      add: [?payment],
      update: [for (final debt in open) debt.withPaidOn(params.on)],
    );
    return written.map(
      (ids) => Settled(reopen: open, paymentId: ids.firstOrNull),
    );
  }

  /// The reason [settlement] cannot be made, or null when it can. Public
  /// and static so the dialog can say it before anything is written.
  static ValidationFailure? validate(Settlement settlement) {
    final open = settlement.person.open;
    if (open.isEmpty) {
      return const ValidationFailure('Nothing is open with them.');
    }
    final day = _day(settlement.on);
    if (day.isAfter(_day(DateTime.now()))) {
      return const ValidationFailure(
        'It cannot be settled in the future.',
        field: 'on',
      );
    }
    if (open.any((debt) => day.isBefore(_day(debt.incurredOn)))) {
      return const ValidationFailure(
        'It cannot be settled before the latest of these began.',
        field: 'on',
      );
    }
    return null;
  }

  /// The payment that settles [settlement]'s net, closed on its day; null
  /// when the two are square.
  static Debt? paymentFor(Settlement settlement) {
    final person = settlement.person;
    final net = person.netCents;
    if (net == 0) return null;
    return Debt(
      // Owed to the user, the person pays them: a record running from the
      // person, as a debt the user owed would.
      direction: net > 0 ? DebtDirection.iOwe : DebtDirection.owedToMe,
      person: person.name,
      amountCents: net.abs(),
      incurredOn: settlement.on,
      paidOn: settlement.on,
      note: paymentNote,
      isPayment: true,
    );
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Takes a settlement back: the records open again as they were, and the
/// payment it wrote gone. FR-DBT-007.
class UndoSettleUp implements UseCase<Unit, Settled> {
  /// Creates the use case.
  const UndoSettleUp(this._repository);

  final DebtRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(Settled params) async =>
      (await _repository.batch(
        update: params.reopen,
        delete: [?params.paymentId],
      )).map((_) => unit);
}
