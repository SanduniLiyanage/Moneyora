import 'package:equatable/equatable.dart';

/// What a card's issuer sets: how much may be owed, the day the statement
/// is cut, the day payment is due, and the yearly interest rate.
/// FR-ACC-008, E-43.
///
/// Every field is optional: a user who knows only the due day enters only
/// that, and each figure that needs a missing one is not shown rather than
/// guessed.
class CreditCardTerms extends Equatable {
  /// Creates the terms.
  const CreditCardTerms({
    this.limitCents,
    this.statementDay,
    this.dueDay,
    this.aprBasisPoints,
  });

  /// No terms: every account that is not a card, and a card until they
  /// are entered.
  static const CreditCardTerms none = CreditCardTerms();

  /// The most that may be owed, in minor units.
  final int? limitCents;

  /// The day of the month the statement is cut, 1 to 31.
  final int? statementDay;

  /// The day of the month payment is due, 1 to 31.
  final int? dueDay;

  /// The yearly interest rate in hundredths of a percent: 2450 is 24.50%.
  final int? aprBasisPoints;

  /// True when nothing has been entered.
  bool get isEmpty =>
      limitCents == null &&
      statementDay == null &&
      dueDay == null &&
      aprBasisPoints == null;

  @override
  List<Object?> get props => [limitCents, statementDay, dueDay, aprBasisPoints];
}
