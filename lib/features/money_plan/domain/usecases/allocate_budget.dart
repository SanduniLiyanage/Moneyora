import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/income_reader.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/allocation_request.dart';
import '../entities/budget_mode.dart';
import '../entities/category_allocation.dart';
import '../entities/category_classification.dart';
import '../entities/category_statistics.dart';
import '../entities/lookback_window.dart';
import '../entities/money_plan_draft.dart';
import '../entities/plan_period.dart';
import '../repositories/money_plan_repository.dart';
import 'classify_categories.dart';
import 'score_confidence.dart';

/// A budget per category for a plan period, a confidence for each, and a
/// total. FR-PLN-007, FR-PLN-008, FR-PLN-009, FR-PLN-010.
///
/// The third stage of the plan generator, over [ClassifyCategories]'
/// output: arithmetic on statistics already computed (E-05), no query of
/// its own except the income Option B needs, read through [IncomeReader].
///
/// Per category, in this order:
///
/// 1. a **monthly base** — the recent average for Fixed, the 60/40
///    weighted moving average otherwise ([recentAverage],
///    [weightedMovingAverage]);
/// 2. the base **for the period** — each month the period touches, weighted
///    by the share of it covered; a month that is one of the category's
///    spike months is budgeted at what it historically costs instead —
///    the overall mean times its own **seasonal multiplier**
///    ([seasonalMultiplier]);
/// 3. the **trend adjustment**, by [CategoryStatistics.trend] and *not* by
///    class ([trendFactor]) — over six months the seed's Car is Fixed *and*
///    rising, and a buffer keyed on class would give it none;
/// 4. a **confidence** from the same statistics and the window
///    ([ScoreConfidence]) — attached, not applied: a Low score changes no
///    figure, it tells the user how far to trust one.
///
/// Then the mode: nothing, or scale every allocation to the user's total
/// (Option A), or fit the non-fixed ones into income less savings less
/// fixed costs (Option B). Rounded to the cent once, at the end of step 3,
/// and again only if a mode rescales.
///
/// Last, **FR-PLN-014's Carry Over arrives here**: when a [MoneyPlanRepository]
/// is given, the plan whose period ended last before this one's start is
/// read, and each category's carried-over overspend is taken off its
/// allocation ([CategoryAllocation.lessCarryOver]) — after the mode, so
/// under Option A the draft sums to the user's total *less* what was
/// already overspent, which is what carrying an overspend forward means;
/// the review screen says so on the card. A category the previous plan
/// carried but the lookback has no spending on is not in the draft and
/// gets no deduction. Without a repository — the engine's own tests, the
/// seed integration tests — no plan is read and nothing is deducted.
class AllocateBudget implements UseCase<MoneyPlanDraft, AllocationRequest> {
  /// Creates the use case over the classifier and the income read, and
  /// [plans] for the previous plan's carry-overs (FR-PLN-014); none when
  /// null.
  const AllocateBudget(this._classify, this._income, {this.plans});

  final ClassifyCategories _classify;
  final IncomeReader _income;

  /// Where the previous plan's carry-overs are read from, or null.
  final MoneyPlanRepository? plans;

  /// How many of the most recent months are "recent": the Fixed average's
  /// window (the SRS's *"average(last 3 occurrences)"*) and the weighted
  /// moving average's 60% part.
  ///
  /// The full lookback mean is *not* used for Fixed on purpose: the one
  /// case where "recent" matters is a fixed cost that stepped — rent that
  /// went up four months ago — and a 24-month mean would budget the old
  /// rent.
  static const int recentMonths = 3;

  /// The weight on the recent months in [weightedMovingAverage].
  static const double recentWeight = 0.60;

  /// The buffer a rising category gets: the SRS's own 8%, inside
  /// FR-PLN-007's 5–10%. A flat figure rather than one scaled to the slope,
  /// because the slope is noisy on short windows and a flat one is
  /// explainable — *"8% more, because this is rising"* (E-07's standard).
  static const double risingFactor = 1.08;

  /// The reduction a falling category gets: the SRS's own 5%.
  static const double fallingFactor = 0.95;

  @override
  Future<Either<Failure, MoneyPlanDraft>> call(AllocationRequest params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    final classified = await _classify(params.lookback);
    return classified.fold(Left.new, (classifications) async {
      final allocations = [
        for (final c in classifications)
          allocate(c, params.lookback, params.period),
      ];
      final drafted = switch (params.mode) {
        UnconstrainedBudget() => Right<Failure, MoneyPlanDraft>(
          MoneyPlanDraft(
            period: params.period,
            lookback: params.lookback,
            mode: params.mode,
            allocations: allocations,
          ),
        ),
        UserTotalBudget(:final totalCents) => _toTotal(
          params,
          allocations,
          totalCents,
        ),
        SuggestedBudget(:final savingsTargetPct) => await _suggested(
          params,
          allocations,
          savingsTargetPct,
        ),
      };
      return drafted.fold(Left.new, _lessCarryOvers);
    });
  }

  /// [draft] with the previous plan's carried-over overspend deducted per
  /// category. FR-PLN-014. Unchanged when there is no repository, no
  /// previous plan, or nothing carried.
  Future<Either<Failure, MoneyPlanDraft>> _lessCarryOvers(
    MoneyPlanDraft draft,
  ) async {
    final plans = this.plans;
    if (plans == null) return Right(draft);
    final read = await plans.getLatestEndingBefore(draft.period.from);
    return read.map((previous) {
      if (previous == null) return draft;
      final carried = {
        for (final a in previous.allocations)
          if (a.carryOverCents > 0) a.categoryId: a.carryOverCents,
      };
      if (carried.isEmpty) return draft;
      final days = draft.period.days;
      final deducted = [
        for (final a in draft.allocations)
          switch (carried[a.categoryId]) {
            null => a,
            final cents => a.lessCarryOver(cents, days: days),
          },
      ];
      if (deducted.every((a) => a.carryOverCents == 0)) return draft;
      return draft.withCarryOvers(deducted, carriedFromPlan: previous.name);
    });
  }

  /// Why [request] cannot be planned, or null when it can. The lookback is
  /// checked by the statistics stage; this checks the rest.
  static ValidationFailure? validate(AllocationRequest request) {
    if (request.period.isInverted) {
      return const ValidationFailure(
        'The start of the plan is after its end.',
        field: 'period',
      );
    }
    return switch (request.mode) {
      UserTotalBudget(:final totalCents) when totalCents < 0 =>
        const ValidationFailure(
          'The total budget cannot be negative.',
          field: 'total',
        ),
      SuggestedBudget(:final savingsTargetPct)
          when savingsTargetPct < 0 || savingsTargetPct > 100 =>
        const ValidationFailure(
          'The savings target is a percentage from 0 to 100.',
          field: 'savingsTargetPct',
        ),
      _ => null,
    };
  }

  // ── the formulas ──────────────────────────────────────────────────────

  /// Mean of the last [recentMonths] monthly totals — all of them when the
  /// window is shorter. The Fixed base.
  static double recentAverage(CategoryStatistics statistics) =>
      _mean(_recent(statistics.monthlyTotalsCents));

  /// [recentWeight] of the recent mean plus the rest of the older mean —
  /// the SRS's weighted moving average. The Variable and Seasonal base.
  ///
  /// With no older months (a window of [recentMonths] or fewer) the 40% has
  /// nothing to weigh, so the recent mean carries the whole allocation
  /// rather than being scaled down to 60% of itself.
  static double weightedMovingAverage(CategoryStatistics statistics) {
    final totals = statistics.monthlyTotalsCents;
    if (totals.length <= recentMonths) return recentAverage(statistics);
    final older = totals.sublist(0, totals.length - recentMonths);
    return recentWeight * _mean(_recent(totals)) +
        (1 - recentWeight) * _mean(older);
  }

  /// How much more than its usual month [statistics] spends in
  /// [calendarMonth]: the mean of that month's totals over the mean of all —
  /// E-07's month-of-year index, from the month's own history. 1.0 when the
  /// window holds no such month, or nothing at all.
  static double seasonalMultiplier(
    CategoryStatistics statistics,
    LookbackWindow window,
    int calendarMonth,
  ) {
    if (statistics.monthCount != window.months || statistics.meanCents <= 0) {
      return 1.0;
    }
    final starts = window.monthStarts;
    final totals = [
      for (var i = 0; i < starts.length; i++)
        if (starts[i].month == calendarMonth) statistics.monthlyTotalsCents[i],
    ];
    if (totals.isEmpty) return 1.0;
    return _mean(totals) / statistics.meanCents;
  }

  /// [risingFactor], [fallingFactor] or 1.0 — by the trend alone.
  static double trendFactor(TrendDirection trend) => switch (trend) {
    TrendDirection.rising => risingFactor,
    TrendDirection.falling => fallingFactor,
    TrendDirection.flat => 1.0,
  };

  /// One category's allocation for [period], unconstrained by any total.
  static CategoryAllocation allocate(
    CategoryClassification classification,
    LookbackWindow window,
    PlanPeriod period,
  ) {
    final statistics = classification.statistics;
    final base = classification.type == ExpenseType.fixed
        ? recentAverage(statistics)
        : weightedMovingAverage(statistics);

    // The index is measured against the overall mean, so it is applied to
    // the overall mean — `mean × mean(month)/mean` is simply what that
    // month costs. Applied to the recency-weighted base instead, a
    // December budget would depend on how quiet the summer was.
    var withSeason = 0.0;
    var withoutSeason = 0.0;
    for (final cover in period.monthCoverage) {
      final monthly = classification.seasonalMonths.contains(cover.month)
          ? statistics.meanCents *
                seasonalMultiplier(statistics, window, cover.month)
          : base;
      withSeason += monthly * cover.fraction;
      withoutSeason += base * cover.fraction;
    }
    final seasonalFactor = withoutSeason == 0
        ? 1.0
        : withSeason / withoutSeason;
    final trend = trendFactor(statistics.trend);
    final cents = (withSeason * trend).round();

    return CategoryAllocation(
      classification: classification,
      baseMonthlyCents: base.round(),
      seasonalFactor: seasonalFactor,
      trendFactor: trend,
      allocationCents: cents,
      dailyAllowanceCents: period.days > 0 ? cents ~/ period.days : 0,
      confidence: ScoreConfidence.score(statistics, window),
    );
  }

  /// [amounts] scaled proportionally so they add up to [total] **exactly**,
  /// in the same order. Largest-remainder rounding: each share is floored,
  /// and the cents that leaves short go one each to the largest fractional
  /// parts, earliest first on a tie. When every amount is zero the total is
  /// shared equally, since there is no proportion to keep.
  static List<int> distribute(List<int> amounts, int total) {
    if (amounts.isEmpty) return const [];
    final sum = amounts.fold(0, (a, b) => a + b);
    final shares = [
      for (final a in amounts)
        sum == 0 ? total / amounts.length : a * total / sum,
    ];
    final floors = [for (final s in shares) s.floor()];
    var short = total - floors.fold(0, (a, b) => a + b);
    final byFraction = List.generate(amounts.length, (i) => i)
      ..sort((a, b) {
        final byPart = (shares[b] - floors[b]).compareTo(shares[a] - floors[a]);
        return byPart != 0 ? byPart : a.compareTo(b);
      });
    for (final i in byFraction) {
      if (short <= 0) break;
      floors[i] += 1;
      short -= 1;
    }
    return floors;
  }

  // ── the modes ─────────────────────────────────────────────────────────

  /// Option A: every allocation scaled to the user's total.
  static Either<Failure, MoneyPlanDraft> _toTotal(
    AllocationRequest request,
    List<CategoryAllocation> allocations,
    int totalCents,
  ) {
    if (allocations.isEmpty && totalCents > 0) {
      return const Left(
        ValidationFailure(
          'There is no spending history to share a total across.',
          field: 'total',
        ),
      );
    }
    final scaled = distribute([
      for (final a in allocations) a.allocationCents,
    ], totalCents);
    return Right(
      MoneyPlanDraft(
        period: request.period,
        lookback: request.lookback,
        mode: request.mode,
        allocations: [
          for (var i = 0; i < allocations.length; i++)
            allocations[i].withAllocation(scaled[i], days: request.period.days),
        ],
      ),
    );
  }

  /// Option B: income for the period, less the savings target, less the
  /// Fixed allocations at face value; the non-fixed categories share the
  /// rest proportionally. The total is then income less savings.
  ///
  /// Income is the lookback's total scaled by months, the way spending is:
  /// a plan for a week is budgeted against a week's worth of income.
  Future<Either<Failure, MoneyPlanDraft>> _suggested(
    AllocationRequest request,
    List<CategoryAllocation> allocations,
    double savingsTargetPct,
  ) async {
    final income = await _income.totalIncome(
      from: request.lookback.from,
      to: request.lookback.to,
    );
    return income.flatMap((lookbackIncome) {
      final periodIncome =
          (lookbackIncome / request.lookback.months * request.period.months)
              .round();
      final savings = (periodIncome * savingsTargetPct / 100).round();
      final fixed = allocations
          .where((a) => a.type == ExpenseType.fixed)
          .fold(0, (sum, a) => sum + a.allocationCents);
      final discretionary = periodIncome - savings - fixed;
      if (discretionary < 0) {
        return const Left(
          ValidationFailure(
            'Fixed costs and the savings target exceed the income for this '
            'period.',
            field: 'savingsTargetPct',
          ),
        );
      }

      final nonFixed = [
        for (final a in allocations)
          if (a.type != ExpenseType.fixed) a,
      ];
      final scaled = distribute([
        for (final a in nonFixed) a.allocationCents,
      ], discretionary);
      var next = 0;
      return Right(
        MoneyPlanDraft(
          period: request.period,
          lookback: request.lookback,
          mode: request.mode,
          incomeCents: periodIncome,
          savingsTargetCents: savings,
          allocations: [
            for (final a in allocations)
              a.type == ExpenseType.fixed
                  ? a
                  : a.withAllocation(scaled[next++], days: request.period.days),
          ],
        ),
      );
    });
  }

  static List<int> _recent(List<int> totals) => totals.length > recentMonths
      ? totals.sublist(totals.length - recentMonths)
      : totals;

  static double _mean(List<int> values) =>
      values.isEmpty ? 0 : values.fold(0, (a, b) => a + b) / values.length;
}
