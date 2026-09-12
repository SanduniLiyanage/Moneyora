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
import '../../../../core/ports/category_reader.dart';
import '../../../../injection.dart';
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

/// What was spent per category over [range]. FR-RPT-001.
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
/// `autoDispose` because it is keyed by [DateRange] and read from one chart;
/// nothing needs the result once that chart leaves the tree.
final spendingByCategoryTotalsProvider = FutureProvider.autoDispose
    .family<List<CategoryTotal>, DateRange>((ref, range) async {
      final getSpendingByCategory = await ref.watch(
        getSpendingByCategoryProvider.future,
      );
      final result = await getSpendingByCategory(range);
      return result.match(
        Future<List<CategoryTotal>>.error,
        Future<List<CategoryTotal>>.value,
      );
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
