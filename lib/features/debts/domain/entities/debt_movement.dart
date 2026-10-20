import 'package:equatable/equatable.dart';

import 'debt.dart';

/// Money that moved into or out of an account because of a debt.
/// FR-DBT-009, E-47.
///
/// A debt naming an account moves it when it begins — lent from it, the
/// money leaves; borrowed into it, the money arrives — and, paid back
/// through an account, moves that one the other way. A payment moves its
/// account once, the way it ran. Each movement is a balance movement, like
/// one side of a transfer: never income or spending (E-02), so the charts,
/// the summary, the reports and the plan never see it, and the account's
/// history shows it so its balance can be explained.
class DebtMovement extends Equatable {
  /// Creates a movement.
  const DebtMovement({
    required this.accountId,
    required this.incoming,
    required this.amountCents,
    required this.on,
    required this.label,
  });

  /// The account it moved.
  final int accountId;

  /// True when the money arrived in the account, false when it left.
  final bool incoming;

  /// How much, in minor units; always positive, [incoming] the sign.
  final int amountCents;

  /// The day it moved.
  final DateTime on;

  /// What the account's history calls it: "Lent to Nimal".
  final String label;

  /// What it does to the account's balance.
  int get deltaCents => incoming ? amountCents : -amountCents;

  /// The movements [debt] makes, in the order they happened: none without
  /// an account; the one when it began; and, once paid back through an
  /// account, the one the other way.
  static List<DebtMovement> of(Debt debt) {
    final person = debt.person.trim();
    final owedToMe = debt.direction == DebtDirection.owedToMe;
    String described(String what) => switch (debt.note?.trim()) {
      final note? when note.isNotEmpty => '$what · $note',
      _ => what,
    };

    final movements = <DebtMovement>[];
    if (debt.accountId case final account?) {
      movements.add(
        DebtMovement(
          accountId: account,
          // Lent, or paid to them: the money left. Borrowed, or paid by
          // them: it arrived.
          incoming: !owedToMe,
          amountCents: debt.amountCents,
          on: debt.incurredOn,
          label: described(switch ((debt.isPayment, owedToMe)) {
            (false, true) => 'Lent to $person',
            (false, false) => 'Borrowed from $person',
            (true, true) => 'Paid back $person',
            (true, false) => '$person paid back',
          }),
        ),
      );
    }
    if ((debt.paidAccountId, debt.paidOn) case (final account?, final day?)
        when !debt.isPayment) {
      movements.add(
        DebtMovement(
          accountId: account,
          // Paid back to the user, the money arrives; paid back by them, it
          // leaves.
          incoming: owedToMe,
          amountCents: debt.amountCents,
          on: day,
          label: described(
            owedToMe ? '$person paid back' : 'Paid back $person',
          ),
        ),
      );
    }
    return movements;
  }

  @override
  List<Object?> get props => [accountId, incoming, amountCents, on, label];
}
