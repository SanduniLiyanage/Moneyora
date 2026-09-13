/// The analytics layer boundary. Exceptions become failures here and nowhere
/// else, exactly as `TransactionRepositoryImpl` does it.
library;

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/ports/income_reader.dart';
import '../../../../core/ports/monthly_spending_reader.dart';
import '../../../../core/ports/spending_by_category_reader.dart';
import '../../domain/entities/analytics_query.dart';
import '../../domain/entities/category_total.dart';
import '../../domain/entities/daily_total.dart';
import '../../domain/entities/trend_point.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../datasources/analytics_local_datasource.dart';

/// Fulfils [AnalyticsRepository] against the local encrypted database.
///
/// It also fulfils [SpendingByCategoryReader], the narrow contract in `core/`
/// that the Copilot reads through, and [MonthlySpendingReader] and
/// [IncomeReader], the ones the Money Plan Generator reads through. One
/// class, several views of the same queries: the feature's own callers get
/// category ids and colours for the chart, and everyone outside the feature
/// gets only what it needs.
///
/// The alternative was an adapter class in `injection.dart`, which would have
/// put a piece of behaviour somewhere nothing can test it.
class AnalyticsRepositoryImpl
    implements
        AnalyticsRepository,
        SpendingByCategoryReader,
        MonthlySpendingReader,
        IncomeReader {
  /// Creates a repository over [local].
  const AnalyticsRepositoryImpl(this._local);

  final AnalyticsLocalDataSource _local;

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) => _attempt(
    () => _local.spendingByCategory(
      from: query.range.from,
      to: query.range.to,
      accountId: query.accountId,
    ),
  );

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) =>
      _attempt(
        () => _local.incomeForPeriod(
          from: query.range.from,
          to: query.range.to,
          accountId: query.accountId,
        ),
      );

  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) => _attempt(
    () => _local.spendingTrend(
      from: query.range.from,
      to: query.range.to,
      granularity: granularity,
      accountId: query.accountId,
    ),
  );

  @override
  Future<Either<Failure, List<DailyTotal>>> dailySpendingTotals(
    AnalyticsQuery query,
  ) => _attempt(
    () => _local.dailySpendingTotals(
      from: query.range.from,
      to: query.range.to,
      accountId: query.accountId,
    ),
  );

  @override
  Future<Either<Failure, Map<String, int>>> totalsByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    // Every account: the Copilot asks about spending, not about where the
    // money sat, and FR-RPT-003's filter is a screen affordance rather than
    // something the port was ever given a way to express.
    final totals = await spendingByCategory(
      AnalyticsQuery(
        range: DateRange(from: from, to: to),
      ),
    );
    // Ids and colours are dropped here rather than by the caller: a port whose
    // whole purpose is to hand data to something off-device should never have
    // been holding an id in the first place.
    return totals.map(
      (rows) => {for (final row in rows) row.name: row.amountCents},
    );
  }

  @override
  Future<Either<Failure, List<MonthlySpending>>> monthlySpendingByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    // Every account, as `totalsByCategory` above: a plan budgets what the
    // person spends, not what one account paid for. The month cut is the
    // trend lines' own statement, so E-02 and E-04 hold here because they
    // hold there.
    final points = await spendingTrend(
      AnalyticsQuery(
        range: DateRange(from: from, to: to),
      ),
      TrendGranularity.month,
    );
    return points.map(
      (rows) => [
        for (final p in rows)
          MonthlySpending(
            categoryId: p.categoryId,
            name: p.name,
            month: p.bucket,
            amountCents: p.amountCents,
            transactionCount: p.transactionCount,
          ),
      ],
    );
  }

  @override
  Future<Either<Failure, int>> totalIncome({
    required DateTime from,
    required DateTime to,
  }) =>
      // Every account, as the other two ports: a plan is budgeted against
      // what the person earns, not what one account received.
      incomeForPeriod(
        AnalyticsQuery(
          range: DateRange(from: from, to: to),
        ),
      );

  Future<Either<Failure, T>> _attempt<T>(Future<T> Function() body) async {
    try {
      return Right(await body());
    } on AppException catch (e) {
      return Left(_toFailure(e));
    }
  }

  static Failure _toFailure(AppException e) => switch (e) {
    CacheException() => CacheFailure(e.message),
    EncryptionException() => EncryptionFailure(e.message),
    ServerException() => ServerFailure(e.message),
    NetworkException() => const NetworkFailure(),
    OcrException() => OcrFailure(e.message),
    PermissionException() => PermissionFailure(e.message),
  };
}
