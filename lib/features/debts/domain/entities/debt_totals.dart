import 'package:equatable/equatable.dart';

import 'debt.dart';
import 'debt_person.dart';

/// What is still owed, each way, across a list of debts. FR-DBT-002,
/// FR-DBT-005.
///
/// Worked out per person first (E-47): what each one owes the user, less
/// what the user owes them. Everyone whose net is in the user's favour is
/// added into [owedToMeCents]; everyone the user owes on balance, into
/// [iOweCents]. Rs1,000 lent to Nimal and Rs400 borrowed from him is
/// Rs600 owed to the user and nothing owed by them, not Rs1,000 and
/// Rs400.
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

  /// The open debts of [debts], netted per person and added up each way,
  /// with how many people are overdue on [today].
  factory DebtTotals.of(Iterable<Debt> debts, {required DateTime today}) =>
      DebtTotals.ofPeople(DebtPerson.group(debts, today: today), today: today);

  /// [people]'s nets added up each way, with how many are overdue on
  /// [today].
  factory DebtTotals.ofPeople(
    Iterable<DebtPerson> people, {
    required DateTime today,
  }) {
    var owedToMe = 0;
    var iOwe = 0;
    var overdue = 0;
    for (final person in people) {
      final net = person.netCents;
      if (net > 0) owedToMe += net;
      if (net < 0) iOwe -= net;
      if (person.isOverdue(today)) overdue++;
    }
    return DebtTotals(
      owedToMeCents: owedToMe,
      iOweCents: iOwe,
      overdue: overdue,
    );
  }

  /// Still owed to the user, by everyone who owes them on balance.
  final int owedToMeCents;

  /// Still owed by the user, to everyone they owe on balance.
  final int iOweCents;

  /// How many people are past a due day on what they still owe, or are
  /// owed.
  final int overdue;

  /// What the user would have if every open debt were settled today:
  /// positive when more is owed to them than by them.
  int get netCents => owedToMeCents - iOweCents;

  @override
  List<Object?> get props => [owedToMeCents, iOweCents, overdue];
}
