import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// Reads total income from the local database.
///
/// Lives in `core/` for the reason [MonthlySpendingReader] does: **analytics**
/// owns the income query and implements this, and the **Money Plan
/// Generator** reads it to suggest a total (FR-PLN-008's Option B), and
/// neither feature may import the other (`check_architecture.sh` rule 4).
///
/// Amounts are integer minor units (E-06).
abstract class IncomeReader {
  /// Total income between [from] and [to], both **inclusive** whole days,
  /// over every account. Zero, not absent, for a period with none.
  ///
  /// Transfers are not income (E-02).
  Future<Either<Failure, int>> totalIncome({
    required DateTime from,
    required DateTime to,
  });
}
