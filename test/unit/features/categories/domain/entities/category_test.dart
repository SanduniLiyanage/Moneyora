import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/categories/domain/entities/category.dart';

/// Equality decides whether Riverpod rebuilds a widget, so a `props` list
/// missing a field produces a screen that silently stops updating when exactly
/// that field changes — close to impossible to diagnose from the symptom.
void main() {
  Category food() => const Category(
    id: 1,
    name: 'Food',
    icon: 'basket',
    colorHex: '#FF9800',
    type: CategoryType.expense,
  );

  group('equality', () {
    test('two identical categories are equal', () {
      expect(food(), food());
      expect(food().hashCode, food().hashCode);
    });

    test('a difference in any field breaks equality', () {
      final base = food();
      final variants = <String, Category>{
        'id': base.copyWith(id: 2),
        'name': base.copyWith(name: 'Groceries'),
        'icon': base.copyWith(icon: 'cart'),
        'colorHex': base.copyWith(colorHex: '#000000'),
        'type': base.copyWith(type: CategoryType.income),
        'parentId': base.copyWith(parentId: 3),
        'isDefault': base.copyWith(isDefault: true),
        'sortOrder': base.copyWith(sortOrder: 5),
      };

      for (final entry in variants.entries) {
        expect(
          entry.value,
          isNot(base),
          reason: '${entry.key} is missing from props',
        );
      }
    });
  });

  group('defaults', () {
    test('a new category is top-level, not a default, sorted first', () {
      const category = Category(
        name: 'Hobbies',
        icon: 'star',
        colorHex: '#673AB7',
        type: CategoryType.expense,
      );

      expect(category.id, isNull);
      expect(category.parentId, isNull);
      expect(category.isDefault, isFalse);
      expect(category.sortOrder, 0);
      expect(category.isChild, isFalse);
    });
  });

  group('isChild', () {
    test('true once a parentId is set', () {
      expect(food().copyWith(parentId: 9).isChild, isTrue);
    });
  });

  group('CategoryType', () {
    test('every type has the storage string the schema CHECK accepts', () {
      const permitted = {'expense', 'income'};

      expect(CategoryType.values.map((t) => t.storageValue).toSet(), permitted);
    });
  });

  group('copyWith', () {
    test('leaves untouched fields alone', () {
      final renamed = food().copyWith(name: 'Groceries');

      expect(renamed.name, 'Groceries');
      expect(renamed.id, 1);
      expect(renamed.colorHex, '#FF9800');
      expect(renamed.type, CategoryType.expense);
    });
  });
}
