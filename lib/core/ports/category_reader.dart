import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// One pickable category, seen from outside `features/categories/`. FR-EXP-003.
///
/// Deliberately narrower than the `Category` entity — no `parentId`,
/// `isDefault` or `sortOrder` — because a consumer outside the categories
/// feature only ever renders a chip, never edits the row. `CategoryWriter`
/// draws the same line in the other direction: primitives in, primitives out,
/// never the entity itself.
class CategoryOption extends Equatable {
  /// Creates a category option.
  const CategoryOption({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.isExpense,
  });

  /// Row id, used as `transactions.category_id`.
  final int id;

  /// What the chip reads.
  final String name;

  /// Icon key, e.g. `basket`.
  final String icon;

  /// `#RRGGBB`, for the chip and the donut chart.
  final String colorHex;

  /// True for spending categories, false for income ones.
  ///
  /// The entry screen shows one set or the other, never both: an expense
  /// filed under Salary is not a mistake worth allowing.
  final bool isExpense;

  @override
  List<Object?> get props => [id, name, icon, colorHex, isExpense];
}

/// Reads the category list from outside `features/categories/`. E-27.
///
/// `features/transactions/` needs every category to render its chips, but may
/// not import `features/categories/` (`check_architecture.sh` rule 4) —
/// categories are shared by analytics, the Money Plan and the receipt
/// scanner too, so the read belongs behind a contract in `core/`, the same
/// role `SpendingByCategoryReader` plays between analytics and the Copilot.
///
/// This replaced `core/database/entry_catalog.dart`'s raw-SQL read once the
/// categories feature slice existed to implement it — see `SPEC_ERRATA.md`
/// E-27.
abstract class CategoryReader {
  /// Watches every category, both expense and income, kept live.
  Stream<Either<Failure, List<CategoryOption>>> watchAll();
}
