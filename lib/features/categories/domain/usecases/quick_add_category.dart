import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/category_writer.dart';
import '../entities/category.dart';
import 'add_category.dart';

/// Fulfils [CategoryWriter] for the entry screen's inline `+`. E-13.
///
/// A thin adapter over [AddCategory] rather than a second write path: the
/// validation and the row it produces are exactly [AddCategory]'s, so a
/// category created here and one created through `CategoryFormPage` can
/// never drift apart on what counts as valid.
///
/// The icon and colour below are literals, not `defaultCategoryIconKey`/
/// `defaultCategoryColorHex` from `core/widgets/category_icons.dart`/`core/
/// theme/category_palette.dart` — both of those import Flutter, which
/// `domain/` may not (`check_architecture.sh` rule 1).
/// `quick_add_category_test.dart` asserts the literals still match, so a
/// change to either catalogue's default cannot drift from this silently.
class QuickAddCategory implements CategoryWriter {
  /// Creates the adapter over [addCategory].
  const QuickAddCategory(this._addCategory);

  final AddCategory _addCategory;

  /// Must match `defaultCategoryIconKey` in `core/widgets/category_icons.dart`.
  static const String defaultIcon = 'other';

  /// Must match `defaultCategoryColorHex` in `core/theme/category_palette.dart`.
  static const String defaultColorHex = '#2a78d6';

  @override
  Future<Either<Failure, int>> call({
    required String name,
    required bool isExpense,
  }) {
    return _addCategory(
      Category(
        name: name,
        icon: defaultIcon,
        colorHex: defaultColorHex,
        type: isExpense ? CategoryType.expense : CategoryType.income,
      ),
    );
  }
}
