/// How far into its budget a category has been announced. FR-SET-007.
///
/// The requirement's two thresholds, plus the state below both. Ordered, so
/// "higher than what was last announced" is a comparison of [index]es:
/// [none] < [warning] < [exceeded].
enum BudgetAlertLevel {
  /// Below 80%. Nothing to say.
  none,

  /// 80% used, not yet 100%. FR-SET-007's "warn".
  warning,

  /// 100% used or more. FR-SET-007's "alert".
  exceeded;

  /// Whether this is past [other].
  bool isAbove(BudgetAlertLevel other) => index > other.index;
}
