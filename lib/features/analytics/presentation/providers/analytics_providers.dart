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
import '../../domain/repositories/analytics_repository.dart';

/// The current calendar month, as a [DateRange].
///
/// The donut chart's only period for this slice — FR-RPT-002's Day/Week/
/// Month/Year/Custom filters are the next Sprint 4 item, not this one. A
/// plain [Provider] rather than a [StateProvider] because nothing can change
/// it yet; swapping it for a `StateProvider<DateRange>` is exactly the change
/// the filter work will make, with no other provider needing to know.
final currentMonthRangeProvider = Provider<DateRange>((ref) {
  final now = DateTime.now();
  return DateRange.month(now.year, now.month);
});

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
