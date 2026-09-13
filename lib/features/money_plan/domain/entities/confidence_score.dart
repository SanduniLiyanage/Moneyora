import 'package:equatable/equatable.dart';

/// How far an allocation can be trusted. FR-PLN-010.
///
/// Declared worst-first so that [index] orders them and a cap is a `min`.
/// Matches `plan_allocations.confidence_level`'s check constraint; the data
/// layer maps to the stored strings.
enum ConfidenceLevel {
  /// Too little data, or too much variance, to budget from with any
  /// certainty.
  low,

  /// Enough to budget from; expect to adjust.
  medium,

  /// Well supported and steady.
  high;

  /// The lower of this and [other].
  ConfidenceLevel cappedAt(ConfidenceLevel other) =>
      index <= other.index ? this : other;
}

/// One allocation's confidence, and the evidence for it. FR-PLN-010, E-07.
///
/// Carries the numbers the level was decided from so the wizard can state
/// the reason — *"Medium: only 6 months of history"* — which E-07 requires
/// when the lookback caps it, and which is worth showing always.
class ConfidenceScore extends Equatable {
  /// Creates a score.
  const ConfidenceScore({
    required this.level,
    required this.uncappedLevel,
    required this.dataPoints,
    required this.coefficientOfVariation,
    required this.lookbackMonths,
  });

  /// The level, after E-07's cap.
  final ConfidenceLevel level;

  /// The level the data alone earned, before the cap. Equal to [level]
  /// unless [isCappedByLookback].
  final ConfidenceLevel uncappedLevel;

  /// The months in which the category was seen — the "data points" the
  /// thresholds count. See `ScoreConfidence` for why months, not rows.
  final int dataPoints;

  /// The variance the thresholds read.
  final double coefficientOfVariation;

  /// The lookback the cap read.
  final int lookbackMonths;

  /// True when the lookback, not the data, held the level down (E-07).
  bool get isCappedByLookback => level != uncappedLevel;

  @override
  List<Object?> get props => [
    level,
    uncappedLevel,
    dataPoints,
    coefficientOfVariation,
    lookbackMonths,
  ];
}
