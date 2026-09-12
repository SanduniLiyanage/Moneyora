/// What an analytics aggregate is asked for. FR-RPT-002, FR-RPT-003.
///
/// The period was the only filter at first, so [DateRange] could be the use
/// case's whole parameter. FR-RPT-003 added a second, and two filters that
/// travel together are one question — a parameter object rather than a second
/// positional argument nobody can read at the call site.
///
/// Named for analytics rather than for spending because FR-RPT-004's
/// income-vs-expense bars ask both aggregates the same question: a chart whose
/// expense bar is narrowed to one account and whose income bar is not compares
/// two different things and calls the difference savings.
library;

import 'package:equatable/equatable.dart';

import '../repositories/analytics_repository.dart';

/// A period, and which account to count. FR-RPT-002, FR-RPT-003.
class AnalyticsQuery extends Equatable {
  /// Creates a query over [range], optionally narrowed to one [accountId].
  const AnalyticsQuery({required this.range, this.accountId});

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
  AnalyticsQuery withRange(DateRange range) =>
      AnalyticsQuery(range: range, accountId: accountId);

  /// This query narrowed to [accountId], or widened to every account when it
  /// is null.
  AnalyticsQuery withAccount(int? accountId) =>
      AnalyticsQuery(range: range, accountId: accountId);

  @override
  List<Object?> get props => [range, accountId];
}
