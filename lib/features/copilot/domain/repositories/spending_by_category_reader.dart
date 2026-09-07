import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';

/// Reads spending totals per category from the local database.
///
/// A port owned by the Copilot rather than a direct call into the analytics
/// feature, for two reasons. Features share code only through `lib/core`, so a
/// tool cannot import `features/analytics` even if it wanted to
/// (`check_architecture.sh` rule 4). And the tool needs one narrow read, not
/// the analytics use case's whole surface — naming exactly what it needs keeps
/// the fake in its test to four lines.
///
/// Amounts are integer minor units (C-4).
abstract class SpendingByCategoryReader {
  /// Totals expense spending between [from] and [to], both **inclusive**
  /// whole days, keyed by category name.
  ///
  /// Categories with no spending in the range are omitted rather than returned
  /// as zero: the result is sent to the model, and a screen full of zeroes is
  /// tokens spent to say nothing.
  ///
  /// Transfers are excluded — they move money between the user's own accounts
  /// and counting them inflates spending (E-02).
  Future<Either<Failure, Map<String, int>>> totalsByCategory({
    required DateTime from,
    required DateTime to,
  });
}
