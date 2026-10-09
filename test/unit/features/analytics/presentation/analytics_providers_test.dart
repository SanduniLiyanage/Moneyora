import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/daily_total.dart';
import 'package:moneyora/features/analytics/domain/entities/transfer_totals.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_income_for_period.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_by_category.dart';
import 'package:moneyora/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:moneyora/injection.dart';

/// Answers with whatever the test last set, so a second read can differ.
class _Scripted implements AnalyticsRepository {
  int spentCents = 0;
  int incomeCents = 0;

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async => Right([
    CategoryTotal(
      categoryId: 1,
      name: 'Food',
      color: '#eb6834',
      amountCents: spentCents,
    ),
  ]);

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) async =>
      Right(incomeCents);

  @override
  Future<Either<Failure, TransferTotals>> transfersForPeriod(
    AnalyticsQuery query,
  ) async => const Right(TransferTotals.none);

  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, List<DailyTotal>>> dailySpendingTotals(
    AnalyticsQuery query,
  ) => throw UnimplementedError();
}

/// Home's figures are futures, so they follow a write only because each
/// one listens to the change bus. FR-RPT-001, FR-RPT-006.
void main() {
  late _Scripted repository;
  late ProviderContainer container;
  final query = AnalyticsQuery(range: DateRange.month(2026, 10));

  setUp(() {
    repository = _Scripted();
    container = ProviderContainer(
      overrides: [
        getSpendingByCategoryProvider.overrideWith(
          (ref) async => GetSpendingByCategory(repository),
        ),
        getIncomeForPeriodProvider.overrideWith(
          (ref) async => GetIncomeForPeriod(repository),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Reads [provider] with a listener held, as a screen holds it, and
  /// returns its value once the query has run.
  Future<T> settled<T>(AutoDisposeFutureProvider<T> provider) async {
    container.listen(provider, (_, _) {});
    return container.read(provider.future);
  }

  test('the spending totals are read again after a write', () async {
    repository.spentCents = 1000;
    expect(
      (await settled(spendingByCategoryTotalsProvider(query)))
          .single
          .amountCents,
      1000,
    );

    repository.spentCents = 2500;
    container.read(databaseChangeBusProvider).notify();
    await Future<void>.delayed(Duration.zero);

    expect(
      (await container.read(spendingByCategoryTotalsProvider(query).future))
          .single
          .amountCents,
      2500,
    );
  });

  test('the income total is read again after a write', () async {
    repository.incomeCents = 500;
    expect(await settled(incomeTotalProvider(query)), 500);

    repository.incomeCents = 900;
    container.read(databaseChangeBusProvider).notify();
    await Future<void>.delayed(Duration.zero);

    expect(await container.read(incomeTotalProvider(query).future), 900);
  });

  test('nothing is read again without a write', () async {
    repository.incomeCents = 500;
    expect(await settled(incomeTotalProvider(query)), 500);

    repository.incomeCents = 900;
    await Future<void>.delayed(Duration.zero);

    expect(await container.read(incomeTotalProvider(query).future), 500);
  });
}
