/// What the spending aggregate is asked for. FR-RPT-002, FR-RPT-003.
///
/// The period was the only filter until now, so [DateRange] could be the use
/// case's whole parameter. FR-RPT-003 adds a second, and two filters that
/// travel together are one question — a parameter object rather than a second
/// positional argument nobody can read at the call site.
library;

import 'package:equatable/equatable.dart';

import '../repositories/analytics_repository.dart';

/// A period, and which account to count. FR-RPT-002, FR-RPT-003.
class SpendingQuery extends Equatable {
  /// Creates a query over [range], optionally narrowed to one [accountId].
  const SpendingQuery({required this.range, this.accountId});

  /// The period to report over. FR-RPT-002.
  final DateRange range;

  /// The one account to count, or null for **All Accounts**. FR-RPT-003.
  ///
  /// Null rather than a sentinel id or a separate `allAccounts` flag: the
  /// requirement offers "All Accounts, or any specific single account", which
  /// is exactly `int?`, and a flag would allow the fourth state (all accounts
  /// *and* an id) that means nothing.
  final int? accountId;

  /// True when this counts every account. FR-RPT-003's "All Accounts".
  bool get isAllAccounts => accountId == null;

  /// This query over [range] instead.
  SpendingQuery withRange(DateRange range) =>
      SpendingQuery(range: range, accountId: accountId);

  /// This query narrowed to [accountId], or widened to every account when it
  /// is null.
  SpendingQuery withAccount(int? accountId) =>
      SpendingQuery(range: range, accountId: accountId);

  @override
  List<Object?> get props => [range, accountId];
}
