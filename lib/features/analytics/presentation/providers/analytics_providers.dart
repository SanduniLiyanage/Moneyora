/// Presentation state for the analytics feature.
///
/// These talk to **use cases and reader ports**, never to a repository or a
/// datasource directly — the rule `scripts/check_architecture.sh` enforces —
/// so a screen can be tested by overriding one provider.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/account_reader.dart';
import '../../../../core/ports/category_reader.dart';
import '../../../../injection.dart';
import '../../domain/entities/analytics_query.dart';
import '../../domain/entities/category_total.dart';
import '../../domain/entities/period_selection.dart';
import '../../domain/repositories/analytics_repository.dart';

/// The period every analytics surface reports over. FR-RPT-002.
///
/// A [StateProvider] because the period picker writes to it — this replaces
/// the hard-coded `currentMonthRangeProvider` the donut chart shipped with
/// (FR-RPT-001), which is exactly the swap that provider's own doc comment
/// said the filter work would make. It holds a [PeriodSelection] rather than
/// a bare [DateRange] so the picker can render which filter is selected
/// without inferring it back out of two dates.
///
/// `DateTime.now()` is read once, here, at the composition root of this
/// state; everything downstream is a pure function of the selection, which
/// is what lets a test state the date instead of working around it.
final analyticsPeriodProvider = StateProvider<PeriodSelection>(
  (ref) => PeriodSelection.monthOf(DateTime.now()),
);

/// The selected period as the [DateRange] the use cases take. FR-RPT-002.
///
/// A derived [Provider] rather than something each widget computes: it keeps
/// the query key identical across every surface watching the same period, so
/// the `family` below is not asked for two ranges that mean one thing.
final analyticsRangeProvider = Provider<DateRange>(
  (ref) => ref.watch(analyticsPeriodProvider).range,
);

/// Which account the analytics surfaces count, or null for **All Accounts**.
/// FR-RPT-003.
///
/// Null rather than a sentinel id, for the same reason [AnalyticsQuery] holds
/// an `int?`: the requirement offers "All Accounts, or any specific single
/// account", and null is that with no fourth state to handle. It opens on
/// All, because the chart it filters is a home-screen summary and a summary
/// that silently omits an account is a wrong total that looks right.
final analyticsAccountFilterProvider = StateProvider<int?>((ref) => null);

/// The two filters as the one question the use case takes.
/// FR-RPT-002, FR-RPT-003.
///
/// Derived rather than assembled at each call site, so every surface watching
/// the same filters keys the `family` below on one identical [AnalyticsQuery]
/// — two equal-but-separate keys would run the query twice and cache it
/// twice.
final analyticsQueryProvider = Provider<AnalyticsQuery>(
  (ref) => AnalyticsQuery(
    range: ref.watch(analyticsRangeProvider),
    accountId: ref.watch(analyticsAccountFilterProvider),
  ),
);

/// What was spent per category over [query]'s period and account.
/// FR-RPT-001, FR-RPT-002, FR-RPT-003.
///
/// Thin wrapper over [GetSpendingByCategory] — the query already exists and
/// is tested against the E-02/E-04 traps; this provider only exposes it as
/// an [AsyncValue] a widget can watch. A `Left` completes the future with
/// the [Failure] as its error, so it arrives as `AsyncValue.error` the same
/// way `accountsProvider`'s `sink.addError` does for a stream — the error
/// *channel*, not a `throw`, because a `Failure` is a value, not an
/// exception (`ARCHITECTURE.md` §3; also what keeps `only_throw_errors`
/// clean here).
///
/// `autoDispose` because it is keyed by [AnalyticsQuery] and read from one
/// chart; nothing needs the result once that chart leaves the tree.
final spendingByCategoryTotalsProvider = FutureProvider.autoDispose
    .family<List<CategoryTotal>, AnalyticsQuery>((ref, query) async {
      final getSpendingByCategory = await ref.watch(
        getSpendingByCategoryProvider.future,
      );
      final result = await getSpendingByCategory(query);
      return result.match(
        Future<List<CategoryTotal>>.error,
        Future<List<CategoryTotal>>.value,
      );
    });

/// Total income over the same period and account. FR-RPT-004.
///
/// Thin wrapper over [GetIncomeForPeriod], which was built and wired in PR #54
/// and called by nothing until FR-RPT-004's bars. Keyed on the same
/// [AnalyticsQuery] the spending provider above uses, so one filter change
/// moves both bars and neither can be left reporting the last period.
///
/// A `Left` completes the future with the [Failure] as its error, the same
/// convention [spendingByCategoryTotalsProvider] follows.
final incomeTotalProvider = FutureProvider.autoDispose
    .family<int, AnalyticsQuery>((ref, query) async {
      final getIncomeForPeriod = await ref.watch(
        getIncomeForPeriodProvider.future,
      );
      final result = await getIncomeForPeriod(query);
      return result.match(Future<int>.error, Future<int>.value);
    });

/// Every category, both kinds, kept live — read through [CategoryReader]
/// rather than `features/categories/`'s own providers, which
/// `features/analytics/` may not import (`check_architecture.sh` rule 4).
///
/// [CategoryTotal] carries a colour but not an icon (the aggregate query
/// never selected one — see `AnalyticsLocalDataSourceImpl`), and FR-RPT-001
/// asks for icons on the chart. Rather than adding a column to a query two
/// features already share, this reads the icon from the same port
/// `entryCategoriesProvider` uses for the entry screen's chips — one read,
/// joined by `categoryId` in the widget below, so no aggregate is written
/// twice (E-24's own reasoning, applied to a reader instead of a use case).
final categoryOptionsProvider =
    StreamProvider.autoDispose<List<CategoryOption>>((ref) {
      return Stream.fromFuture(ref.watch(categoryReaderProvider.future))
          .asyncExpand((reader) => reader.watchAll())
          .transform(
            StreamTransformer<
              Either<Failure, List<CategoryOption>>,
              List<CategoryOption>
            >.fromHandlers(
              handleData: (result, sink) =>
                  result.match(sink.addError, sink.add),
            ),
          );
    });

/// Every non-archived account, for FR-RPT-003's picker — read through
/// [AccountReader] rather than `features/accounts/`'s own providers, which
/// `features/analytics/` may not import (`check_architecture.sh` rule 4).
///
/// The same port `entryAccountsProvider` already reads for the entry screen,
/// for the same reason `categoryOptionsProvider` above reads [CategoryReader]:
/// a picker needs names, and the aggregate query has never selected one.
final accountOptionsProvider = StreamProvider.autoDispose<List<AccountOption>>((
  ref,
) {
  return Stream.fromFuture(ref.watch(accountReaderProvider.future))
      .asyncExpand((reader) => reader.watchAll())
      .transform(
        StreamTransformer<
          Either<Failure, List<AccountOption>>,
          List<AccountOption>
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});
