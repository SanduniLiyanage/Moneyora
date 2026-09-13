import '../entities/category_statistics.dart';
import '../entities/confidence_score.dart';
import '../entities/lookback_window.dart';

/// High / Medium / Low for one allocation, from data sufficiency and
/// variance. FR-PLN-010, E-07.
///
/// The fourth stage of the plan generator, and pure arithmetic over the
/// statistics the first computed (E-05). Static, because it has nothing to
/// read: `AllocateBudget` calls [score] for each allocation it builds.
///
/// ## "Data points" are months, not rows
///
/// The SDD scores on `data_points` without saying what one is.
/// [CategoryStatistics] offers two counts, and this reads
/// [CategoryStatistics.activeMonths] — the months in which the category was
/// seen — not [CategoryStatistics.transactionCount].
///
/// An allocation is a *monthly* figure estimated from *monthly* totals, so
/// its statistical support is the number of monthly observations. The
/// seed's Food has 521 rows in 24 months: that is 24 observations of the
/// thing being estimated. Rows within a month make that month's total less
/// noisy, which the CV already reflects; they are not further evidence
/// about the next month. Counted as rows, twelve receipts in one
/// shopping-spree month would read as twelve data points on one
/// observation, and a category bought daily would reach High on a single
/// month of history.
///
/// Two consequences follow, and both are wanted. `activeMonths` never
/// exceeds the window, so High (ten or more) is unreachable under the
/// six-month default — which is what E-07 requires anyway, so the two
/// rules agree rather than the cap doing the sufficiency rule's work. And
/// the cap is only *binding* for windows of ten to twenty-three months,
/// where the data alone could earn High.
///
/// ## Thresholds and cap
///
/// The SDD's bands, read with strict `<` on the CV — a CV of exactly 0.25
/// is not under 0.25 — and E-07's rule that below a full 24-month lookback
/// the level cannot exceed Medium, applied after the bands as a `min`.
class ScoreConfidence {
  ScoreConfidence._();

  /// Months of history High needs.
  static const int highMinMonths = 10;

  /// The CV High must stay under.
  static const double highMaxCv = 0.25;

  /// Months of history Medium needs.
  static const int mediumMinMonths = 4;

  /// The CV Medium must stay under.
  static const double mediumMaxCv = 0.50;

  /// The score for [statistics] over [window].
  static ConfidenceScore score(
    CategoryStatistics statistics,
    LookbackWindow window,
  ) {
    final months = statistics.activeMonths;
    final cv = statistics.coefficientOfVariation;

    final earned = months >= highMinMonths && cv < highMaxCv
        ? ConfidenceLevel.high
        : months >= mediumMinMonths && cv < mediumMaxCv
        ? ConfidenceLevel.medium
        : ConfidenceLevel.low;

    // E-07: seasonal detection is only honest at 24 months, and so is High.
    final cap = window.months < LookbackWindow.maxMonths
        ? ConfidenceLevel.medium
        : ConfidenceLevel.high;

    return ConfidenceScore(
      level: earned.cappedAt(cap),
      uncappedLevel: earned,
      dataPoints: months,
      coefficientOfVariation: cv,
      lookbackMonths: window.months,
    );
  }
}
