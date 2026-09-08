import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// Reads spending totals per category from the local database.
///
/// Lives in `core/` because two features need it and neither may import the
/// other (`check_architecture.sh` rule 4): **analytics** owns the query and
/// implements this, and the **Copilot** consumes it to answer questions about
/// spending. A contract in the middle is what keeps the dependency from
/// running either way.
///
/// Deliberately narrower than the analytics repository it is implemented by.
/// A caller of this port gets totals by name and nothing else — no category
/// ids, no colours, no rows — which is the shape the Copilot may send onward
/// (FR-COP-010) and all the shape it needs.
///
/// Amounts are integer minor units (E-06).
abstract class SpendingByCategoryReader {
  /// Totals expense spending between [from] and [to], both **inclusive** whole
  /// days, keyed by category name.
  ///
  /// Categories with nothing spent in the range are omitted rather than
  /// returned as zero — a caller that sends this to a language model would be
  /// paying for tokens that say nothing.
  ///
  /// Transfers are excluded: they move money between the user's own accounts,
  /// and counting them inflates spending (E-02).
  Future<Either<Failure, Map<String, int>>> totalsByCategory({
    required DateTime from,
    required DateTime to,
  });
}
