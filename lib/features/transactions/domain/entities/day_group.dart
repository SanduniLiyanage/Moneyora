import 'package:equatable/equatable.dart';

import 'transaction.dart';

/// The transactions of one calendar day, and what the day cost. FR-EXP-006.
///
/// FR-EXP-006 asks for the list "grouped by date with collapsible date
/// section headers showing daily totals": the header is what lets someone
/// see what a day cost without adding it up. Like [CategoryGroup]s, this is
/// a pure regrouping of the rows the list already has, not a query.
class DayGroup extends Equatable {
  /// Creates a group.
  const DayGroup({required this.day, required this.transactions});

  /// The day, at local midnight.
  final DateTime day;

  /// Newest first, in the order the list was given them.
  final List<Transaction> transactions;

  /// How many rows the day holds, transfers included.
  int get count => transactions.length;

  /// What was spent that day, in minor units. A split counts whole, since
  /// its parts add up to it (E-04); transfers never count (E-02).
  int get spentCents => _sum(TransactionType.expense);

  /// What came in that day, in minor units. Transfers never count (E-02).
  int get incomeCents => _sum(TransactionType.income);

  /// Transferred in that day, in minor units — never income (E-02). Only
  /// meaningful for one account's rows; across every account each
  /// transfer's legs cancel. FR-TRF-004.
  int get transferInCents => _transfers(TransferDirection.incoming);

  /// Transferred out that day, in minor units — never spending (E-02).
  int get transferOutCents => _transfers(TransferDirection.out);

  int _sum(TransactionType type) => transactions
      .where((t) => t.type == type)
      .fold(0, (sum, t) => sum + t.amountCents);

  int _transfers(TransferDirection direction) => transactions
      .where(
        (t) =>
            t.type == TransactionType.transfer &&
            t.transferDirection == direction,
      )
      .fold(0, (sum, t) => sum + t.amountCents);

  /// Groups [transactions] by the calendar day each happened on, keeping
  /// their order: given newest first, the days come newest first, and so do
  /// the rows inside each.
  static List<DayGroup> group(Iterable<Transaction> transactions) {
    final byDay = <DateTime, List<Transaction>>{};
    for (final t in transactions) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      (byDay[day] ??= []).add(t);
    }
    return [
      for (final MapEntry(:key, :value) in byDay.entries)
        DayGroup(day: key, transactions: List.unmodifiable(value)),
    ];
  }

  @override
  List<Object?> get props => [day, transactions];
}
