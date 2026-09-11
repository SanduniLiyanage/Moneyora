@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/categories/domain/entities/category.dart';
import 'package:moneyora/features/categories/presentation/pages/category_form_page.dart';
import 'package:moneyora/features/categories/presentation/pages/category_list_page.dart';
import 'package:moneyora/features/categories/presentation/providers/category_providers.dart';

/// The category management screen, over a scripted category list.
///
/// The same shape as `accounts_drawer_test.dart`: the arithmetic and
/// filtering already have their own unit tests, so what is checked here is
/// what a person can actually read — that expense and income stay on their
/// own tabs, and that a sub-category renders under its parent rather than
/// beside it.
void main() {
  Category category({
    required int id,
    String name = 'Food',
    CategoryType type = CategoryType.expense,
    int? parentId,
  }) => Category(
    id: id,
    name: name,
    icon: 'basket',
    colorHex: '#7b5ea7',
    type: type,
    parentId: parentId,
  );

  /// Boots the list page behind a router, so `context.push` has somewhere to
  /// go — a bare `MaterialApp(home: ...)` has no navigator stack entry to
  /// push a new route onto.
  Widget boot({
    List<Category>? expense,
    List<Category>? income,
    Object? failure,
  }) {
    Stream<List<Category>> streamOf(List<Category>? value) {
      if (failure != null) return Stream<List<Category>>.error(failure);
      return Stream<List<Category>>.value(value ?? const []);
    }

    final router = GoRouter(
      initialLocation: Routes.categories,
      routes: [
        GoRoute(
          path: Routes.categories,
          builder: (context, state) => const CategoryListPage(),
        ),
        GoRoute(
          path: Routes.categoryForm,
          builder: (context, state) => switch (state.extra) {
            final Category c => CategoryFormPage(initial: c),
            final CategoryType t => CategoryFormPage(initialType: t),
            _ => const CategoryFormPage(),
          },
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        categoriesProvider(CategoryType.expense)
            .overrideWith((ref) => streamOf(expense)),
        categoriesProvider(CategoryType.income)
            .overrideWith((ref) => streamOf(income)),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
  }

  group('the expense tab', () {
    testWidgets('lists top-level categories', (tester) async {
      await tester.pumpWidget(
        boot(
          expense: [
            category(id: 1, name: 'Food'),
            category(id: 2, name: 'Bills'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Bills'), findsOneWidget);
    });

    testWidgets('nests a sub-category under its parent', (tester) async {
      await tester.pumpWidget(
        boot(
          expense: [
            category(id: 1, name: 'Food'),
            category(id: 2, name: 'Snacks', parentId: 1),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final parentTop = tester.getTopLeft(find.text('Food')).dy;
      final childTop = tester.getTopLeft(find.text('Snacks')).dy;
      final parentLeft = tester.getTopLeft(find.text('Food')).dx;
      final childLeft = tester.getTopLeft(find.text('Snacks')).dx;

      // The child renders below its parent and indented further right,
      // which is what makes FR-EXP-005's hierarchy visible rather than
      // merely storable.
      expect(childTop, greaterThan(parentTop));
      expect(childLeft, greaterThan(parentLeft));
    });

    testWidgets('shows nothing yet when there are none', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      expect(find.text('No categories of this kind yet.'), findsOneWidget);
    });

    testWidgets('shows the failure it was given', (tester) async {
      await tester.pumpWidget(
        boot(failure: const CacheFailure('The database is locked.')),
      );
      await tester.pumpAndSettle();

      expect(find.text('The database is locked.'), findsOneWidget);
    });
  });

  group('the two tabs', () {
    testWidgets('keep expense and income separate', (tester) async {
      await tester.pumpWidget(
        boot(
          expense: [category(id: 1, name: 'Food')],
          income: [category(id: 2, name: 'Salary', type: CategoryType.income)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Food'), findsNothing);
    });
  });

  group('navigating', () {
    testWidgets('opens a tapped category for editing', (tester) async {
      await tester.pumpWidget(boot(expense: [category(id: 1, name: 'Food')]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();

      expect(find.text('Edit category'), findsOneWidget);
    });

    testWidgets(
      'the add button opens a new category of the visible tab\'s type',
      (tester) async {
        // The list page has two tabs; the form has one type toggle. Pressing
        // Add on the Income tab must not hand back an Expense form — the
        // button reads which tab is showing rather than always defaulting.
        await tester.pumpWidget(boot());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Income'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(find.text('New category'), findsOneWidget);
        final segmented = tester.widget<SegmentedButton<CategoryType>>(
          find.byType(SegmentedButton<CategoryType>),
        );
        expect(segmented.selected, {CategoryType.income});
      },
    );
  });
}
