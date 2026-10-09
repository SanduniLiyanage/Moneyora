import 'package:equatable/equatable.dart';

import 'debt.dart';

/// What is still owed, each way, across a list of debts. FR-DBT-002.
///
/// Paid debts count for nothing: the totals answer "who still owes what",
/// which is the question the list is opened to ask.
class DebtTotals extends Equatable {
  /// Creates totals.
  const DebtTotals({
    required this.owedToMeCents,
    required this.iOweCents,
    required this.overdue,
  });

  /// The open debts of [debts], added up each way, with how many of them
  /// are past their due day on [today].
  factory DebtTotals.of(Iterable<Debt> debts, {required DateTime today}) {
    var owedToMe = 0;
    var iOwe = 0;
    var overdue = 0;
    for (final debt in debts) {
      if (!debt.isOpen) continue;
      switch (debt.direction) {
        case DebtDirection.owedToMe:
          owedToMe += debt.amountCents;
        case DebtDirection.iOwe:
          iOwe += debt.amountCents;
      }
      if (debt.isOverdue(today)) overdue++;
    }
    return DebtTotals(
      owedToMeCents: owedToMe,
      iOweCents: iOwe,
      overdue: overdue,
    );
  }

  /// Still owed to the user.
  final int owedToMeCents;

  /// Still owed by the user.
  final int iOweCents;

  /// How many open debts are past their due day.
  final int overdue;

  /// What the user would have if every open debt were settled today:
  /// positive when more is owed to them than by them.
  int get netCents => owedToMeCents - iOweCents;

  @override
  List<Object?> get props => [owedToMeCents, iOweCents, overdue];
}
