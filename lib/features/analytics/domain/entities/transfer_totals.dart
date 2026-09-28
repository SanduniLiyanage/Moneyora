import 'package:equatable/equatable.dart';

/// Money moved into and out of one account by transfers over a period.
/// FR-TRF-004.
///
/// Neither income nor spending (E-02): nothing here ever reaches a spending
/// chart, the plan or a budget. It exists for one question — how much money
/// is in *this* account now — which a transfer does change. Cash drawn from
/// a card is money gone from the card and money arrived in cash, and the
/// person looking at either account expects to see it move.
///
/// Across every account the two legs of each transfer cancel, which is why
/// the summary only asks for these when one account is chosen.
class TransferTotals extends Equatable {
  /// Creates the totals, both in the account's own minor units.
  const TransferTotals({required this.inCents, required this.outCents});

  /// No transfers either way.
  static const none = TransferTotals(inCents: 0, outCents: 0);

  /// Transferred into the account.
  final int inCents;

  /// Transferred out of the account.
  final int outCents;

  @override
  List<Object?> get props => [inCents, outCents];
}
