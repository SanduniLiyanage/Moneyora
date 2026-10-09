import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/debt.dart';
import '../repositories/debt_repository.dart';
import 'save_debt.dart';

/// A bill shared by the user and [others]. Input to [SplitBill].
class SplitRequest extends Equatable {
  /// Creates the request.
  const SplitRequest({
    required this.totalCents,
    required this.others,
    required this.on,
    this.paidBy,
    this.note,
  });

  /// The whole bill, in minor units.
  final int totalCents;

  /// Everyone who shares it besides the user, by name.
  final List<String> others;

  /// Which of [others] paid it, by position; null when the user did.
  final int? paidBy;

  /// The day it was paid.
  final DateTime on;

  /// What it was for: "Dinner".
  final String? note;

  /// How many share it, the user included.
  int get people => others.length + 1;

  @override
  List<Object?> get props => [totalCents, others, paidBy, on, note];
}

/// A bill split evenly, and what follows from who paid it: the debts.
/// FR-DBT-004, E-44.
///
/// The total is divided by the number of people, in whole minor units:
/// the cents that do not divide go one each to the first people, the user
/// first, so the shares add up to the bill exactly (E-06).
///
/// Who owes whom follows from who paid:
/// - **The user paid**: each of the others owes the user their share, one
///   debt each, owed to the user.
/// - **One of the others paid**: the user owes that person their own
///   share, one debt. What the others owe the payer is between them, and
///   not the user's to record.
///
/// All the debts are written together or not at all: half a split is a
/// list that no longer adds up to the bill.
class SplitBill implements UseCase<List<int>, SplitRequest> {
  /// Creates the use case.
  const SplitBill(this._repository);

  final DebtRepository _repository;

  /// The most people one bill is split between: enough for a big table,
  /// few enough to fit the screen.
  static const int maxPeople = 20;

  @override
  Future<Either<Failure, List<int>>> call(SplitRequest params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);
    return _repository.addAll(debtsFor(params));
  }

  /// The reason [request] cannot be split, or null when it can. Public and
  /// static so the screen can say it as the user types.
  static ValidationFailure? validate(SplitRequest request) {
    if (request.totalCents <= 0) {
      return const ValidationFailure(
        'Enter the total of the bill.',
        field: 'total',
      );
    }
    if (request.others.isEmpty) {
      return const ValidationFailure(
        'Add someone to split it with.',
        field: 'people',
      );
    }
    if (request.people > maxPeople) {
      return const ValidationFailure(
        'At most $maxPeople people share one bill.',
        field: 'people',
      );
    }
    if (request.others.any((name) => name.trim().isEmpty)) {
      return const ValidationFailure('Give everyone a name.', field: 'people');
    }
    if (request.others.any(
      (name) => name.trim().length > SaveDebt.maxPersonLength,
    )) {
      return const ValidationFailure(
        'A name is too long - ${SaveDebt.maxPersonLength} characters at most.',
        field: 'people',
      );
    }
    final payer = request.paidBy;
    if (payer != null && (payer < 0 || payer >= request.others.length)) {
      return const ValidationFailure('Choose who paid.', field: 'paidBy');
    }
    final today = DateTime.now();
    if (DateTime(
      request.on.year,
      request.on.month,
      request.on.day,
    ).isAfter(DateTime(today.year, today.month, today.day))) {
      return const ValidationFailure(
        'A bill cannot be paid in the future.',
        field: 'on',
      );
    }
    return null;
  }

  /// [totalCents] in [people] shares that add up to it exactly: the first
  /// `totalCents % people` shares a cent larger.
  static List<int> shares(int totalCents, int people) {
    final each = totalCents ~/ people;
    final left = totalCents % people;
    return [for (var i = 0; i < people; i++) each + (i < left ? 1 : 0)];
  }

  /// The debts [request] leaves, in the order of [SplitRequest.others].
  static List<Debt> debtsFor(SplitRequest request) {
    final split = shares(request.totalCents, request.people);
    final what = switch (request.note?.trim()) {
      final note? when note.isNotEmpty => note,
      _ => 'A bill',
    };
    final note = '$what, split ${request.people} ways';
    final payer = request.paidBy;

    if (payer != null) {
      return [
        Debt(
          direction: DebtDirection.iOwe,
          person: request.others[payer].trim(),
          // The user's share is the first.
          amountCents: split.first,
          incurredOn: request.on,
          note: note,
        ),
      ];
    }
    return [
      for (final (i, name) in request.others.indexed)
        Debt(
          direction: DebtDirection.owedToMe,
          person: name.trim(),
          amountCents: split[i + 1],
          incurredOn: request.on,
          note: note,
        ),
    ];
  }
}
