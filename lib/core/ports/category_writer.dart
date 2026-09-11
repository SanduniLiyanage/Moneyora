import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// Creates a category from outside `features/categories/`. E-13, FR-EXP-004.
///
/// The entry screen's inline `+` needs a write path through the categories
/// repository, not one of its own — SPEC_ERRATA.md's E-13 resolution is
/// explicit that a read or write bypassing that slice is how two sources of
/// truth start. `features/transactions/` may not import `features/
/// categories/` either way (`check_architecture.sh` rule 4), so this is the
/// seam between them, the same role `SpendingByCategoryReader` plays between
/// analytics and the Copilot.
///
/// Takes only primitives, never the `Category` entity — a consumer outside
/// the categories feature must never need that feature's domain types.
abstract class CategoryWriter {
  /// Creates a top-level category named [name], returning its row id.
  ///
  /// Starts with the catalogue's default icon and colour, and no parent:
  /// quick creation is for the moment a name is needed, not for choosing
  /// one — the categories screen is where those get refined. Runs the same
  /// validation every other write to this table runs, so a blank or
  /// too-long name is refused here exactly as it would be there.
  Future<Either<Failure, int>> call({
    required String name,
    required bool isExpense,
  });
}
