import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/category_palette.dart';
import '../../../../core/widgets/category_icons.dart';
import '../../domain/entities/category.dart';
import '../providers/category_providers.dart';

/// Managing categories. FR-EXP-004, FR-EXP-005.
///
/// A page rather than a drawer, unlike `AccountDrawer` — this is a screen a
/// user visits deliberately to organise their categories, not a panel they
/// pop in and out of while entering a transaction.
///
/// Expense and income are shown as separate tabs rather than one long list
/// with both mixed in, the same reasoning the entry screen's category chips
/// already follow: a category picker shows one set or the other, never both,
/// because an expense filed under Salary is not a mistake worth allowing.
/// Sub-categories are nested under their parent, which is what makes
/// FR-EXP-005's hierarchy visible rather than merely storable.
class CategoryListPage extends StatelessWidget {
  /// Creates the category management screen.
  const CategoryListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Expense'),
              Tab(text: 'Income'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CategoryTab(type: CategoryType.expense),
            _CategoryTab(type: CategoryType.income),
          ],
        ),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton(
            onPressed: () => context.push(
              Routes.categoryForm,
              extra: _newCategoryFor(context),
            ),
            tooltip: 'Add category',
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }

  /// The type of a new category follows whichever tab is showing, so the
  /// button on the Income tab does not hand back an Expense form.
  CategoryType _newCategoryFor(BuildContext context) =>
      DefaultTabController.of(context).index == 0
      ? CategoryType.expense
      : CategoryType.income;
}

class _CategoryTab extends ConsumerWidget {
  const _CategoryTab({required this.type});

  final CategoryType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider(type));

    return switch (categories) {
      AsyncData(:final value) => _Categories(categories: value),
      AsyncError(:final error) => _Problem(error: error),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Categories extends StatelessWidget {
  const _Categories({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const _NoCategories();

    final topLevel = categories.where((c) => !c.isChild).toList();
    final childrenOf = <int, List<Category>>{};
    for (final category in categories) {
      final parentId = category.parentId;
      if (parentId != null) {
        (childrenOf[parentId] ??= []).add(category);
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final parent in topLevel) ...[
          _CategoryTile(category: parent),
          for (final child in childrenOf[parent.id] ?? const <Category>[])
            _CategoryTile(category: child, indented: true),
        ],
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, this.indented = false});

  final Category category;

  /// True for a sub-category, so it renders under its parent rather than
  /// looking like one more top-level entry.
  final bool indented;

  @override
  Widget build(BuildContext context) {
    final color = categoryColorFor(
      category.colorHex,
      Theme.of(context).brightness,
    );

    return ListTile(
      contentPadding: EdgeInsets.only(left: indented ? 48 : 16, right: 16),
      leading: CircleAvatar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        child: Icon(categoryIconFor(category.icon), size: 20),
      ),
      title: Text(category.name),
      onTap: () => context.push(Routes.categoryForm, extra: category),
    );
  }
}

class _NoCategories extends StatelessWidget {
  const _NoCategories();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: Text('No categories of this kind yet.')),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            // A Failure carries its own message precisely so the UI never has
            // to invent one; anything else reaching here is a bug rather than
            // something to explain to the user.
            switch (error) {
              final Failure failure => failure.message,
              _ => 'Could not load your categories.',
            },
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
