@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/categories/domain/entities/category.dart';
import 'package:moneyora/features/categories/domain/repositories/category_repository.dart';
import 'package:moneyora/features/categories/presentation/pages/category_form_page.dart';
import 'package:moneyora/injection.dart';

/// The category form, driven the way a person drives it.
///
/// The repository is a fake; everything above it is real — the widgets, the
/// providers, and the actual `AddCategory` and `UpdateCategory` use cases with
/// their validation. That is the point, the same reasoning `account_form_test
/// .dart` gives: the messages asserted here are the use case's own, so a rule
/// cannot drift between the form and the thing that enforces it.
class _FakeRepository implements CategoryRepository {
  final List<Category> added = [];
  final List<Category> updated = [];
  final List<int> deleted = [];

  /// What `list`/`watch` return, keyed by [CategoryType]. `find` and the
  /// parent dropdown both read from here.
  List<Category> existing = const [];

  /// What `usageCount` returns for any id.
  int usage = 0;

  /// What `childCount` returns for any id.
  int children = 0;

  /// Set to make the next write fail, as a locked database would.
  Failure? failWith;

  @override
  Future<Either<Failure, int>> add(Category category) async {
    if (failWith case final failure?) return Left(failure);
    added.add(category);
    return const Right(7);
  }

  @override
  Future<Either<Failure, Unit>> update(Category category) async {
    if (failWith case final failure?) return Left(failure);
    updated.add(category);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    if (failWith case final failure?) return Left(failure);
    deleted.add(id);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Category?>> find(int id) async {
    for (final category in existing) {
      if (category.id == id) return Right(category);
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, int>> usageCount(int id) async => Right(usage);

  @override
  Future<Either<Failure, int>> childCount(int id) async => Right(children);

  @override
  Future<Either<Failure, List<Category>>> list({CategoryType? type}) async =>
      Right(
        type == null
            ? existing
            : existing.where((c) => c.type == type).toList(),
      );

  @override
  Stream<Either<Failure, List<Category>>> watch({CategoryType? type}) =>
      Stream.value(
        type == null
            ? existing
            : existing.where((c) => c.type == type).toList(),
      ).map(Right.new);
}

void main() {
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());

  Category topLevel({
    required int id,
    String name = 'Food',
    CategoryType type = CategoryType.expense,
  }) => Category(
    id: id,
    name: name,
    icon: 'basket',
    colorHex: '#7b5ea7',
    type: type,
  );

  /// A plain, top-level category — the fixture for tests that are not about
  /// the hierarchy.
  Category existingCategory() => const Category(
    id: 4,
    name: 'Snacks',
    icon: 'basket',
    colorHex: '#7b5ea7',
    type: CategoryType.expense,
  );

  /// A sub-category of `topLevel(id: 1)` — for the parent-dropdown tests,
  /// which need a real parent in `repository.existing` to resolve against.
  Category childCategory() => const Category(
    id: 5,
    name: 'Snacks',
    icon: 'basket',
    colorHex: '#7b5ea7',
    type: CategoryType.expense,
    parentId: 1,
  );

  /// Gives the form a viewport tall enough to hold all of it at once — the
  /// same reasoning `account_form_test.dart` gives: the default 800x600 is
  /// shorter than this form, and a `ListView` builds lazily, so the buttons
  /// below the fold do not exist to be tapped until something scrolls first.
  void useTallViewport(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget boot({
    Category? initial,
    CategoryType initialType = CategoryType.expense,
  }) => ProviderScope(
    overrides: [
      categoryRepositoryProvider.overrideWith((ref) async => repository),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: CategoryFormPage(initial: initial, initialType: initialType),
    ),
  );

  Future<void> open(
    WidgetTester tester, {
    Category? initial,
    CategoryType initialType = CategoryType.expense,
  }) async {
    useTallViewport(tester);
    await tester.pumpWidget(boot(initial: initial, initialType: initialType));
    await tester.pumpAndSettle();
  }

  group('creating a category', () {
    testWidgets('writes what was typed', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Groceries');
      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();

      expect(repository.added, hasLength(1));
      expect(repository.added.single.name, 'Groceries');
      expect(repository.added.single.id, isNull);
    });

    testWidgets('refuses an empty name with the use case\'s own words', (
      tester,
    ) async {
      // AddCategory.validate owns this sentence.
      await open(tester);

      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();

      expect(find.text('Give the category a name.'), findsOneWidget);
      expect(repository.added, isEmpty);
    });

    testWidgets('says nothing about the name before Save is pressed', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Give the category a name.'), findsNothing);
    });

    testWidgets('starts on the type the list page\'s tab handed it', (
      tester,
    ) async {
      await open(tester, initialType: CategoryType.income);

      await tester.enterText(find.byType(TextField), 'Bonus');
      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();

      expect(repository.added.single.type, CategoryType.income);
    });

    testWidgets('starts on the catalogue default icon and colour', (
      tester,
    ) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Misc');
      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();

      expect(repository.added.single.icon, 'other');
      expect(repository.added.single.colorHex, '#2a78d6');
    });

    testWidgets('shows the failure instead of pretending it saved', (
      tester,
    ) async {
      repository.failWith = const CacheFailure('The database is locked.');

      await open(tester);

      await tester.enterText(find.byType(TextField), 'Groceries');
      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();

      expect(find.text('The database is locked.'), findsOneWidget);
      expect(find.text('New category'), findsOneWidget);
    });
  });

  group('the parent dropdown', () {
    testWidgets('offers only top-level categories of the same type', (
      tester,
    ) async {
      repository.existing = [
        topLevel(id: 1, name: 'Food'),
        topLevel(id: 2, name: 'Salary', type: CategoryType.income),
        childCategory(), // a child — must not appear as a choosable parent
      ];
      await open(tester);

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      expect(find.text('Food').last, findsOneWidget);
      expect(find.text('Salary'), findsNothing);
      expect(find.text('Snacks'), findsNothing);
    });

    testWidgets('does not offer a category as its own parent', (tester) async {
      repository.existing = [topLevel(id: 1, name: 'Food')];
      await open(tester, initial: topLevel(id: 1, name: 'Food'));

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      // Only "None" is on offer — the category being edited is excluded from
      // its own parent dropdown. "Food" still appears once, in the name
      // field the form was opened with; the dropdown must not add a second.
      expect(find.text('Food'), findsOneWidget);
    });

    testWidgets('preselects the current parent when editing a sub-category', (
      tester,
    ) async {
      // Regressed once: `DropdownButtonFormField` asserts if its
      // `initialValue` is not among its `items`, which briefly happens here
      // — the parent list loads asynchronously, one frame after the id it
      // needs to validate against arrives.
      repository.existing = [topLevel(id: 1, name: 'Food')];
      await open(tester, initial: childCategory());

      expect(find.text('Food'), findsOneWidget);
    });
  });

  group('switching type', () {
    testWidgets('clears the parent, since it must match the new type', (
      tester,
    ) async {
      repository.existing = [topLevel(id: 1, name: 'Food')];
      await open(tester, initial: childCategory());

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Refund');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(repository.updated.single.parentId, isNull);
      expect(repository.updated.single.type, CategoryType.income);
    });
  });

  group('editing a category', () {
    testWidgets('opens with the category already filled in', (tester) async {
      await open(tester, initial: existingCategory());

      expect(find.text('Edit category'), findsOneWidget);
      expect(find.text('Snacks'), findsOneWidget);
    });

    testWidgets('updates rather than adding a second category', (tester) async {
      await open(tester, initial: existingCategory());

      await tester.enterText(find.byType(TextField), 'Renamed snacks');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(repository.added, isEmpty);
      expect(repository.updated, hasLength(1));
      expect(repository.updated.single.id, 4);
      expect(repository.updated.single.name, 'Renamed snacks');
    });
  });

  group('the icon picker', () {
    testWidgets('offers the catalogue and saves the chosen key', (
      tester,
    ) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Streaming');
      await tester.tap(find.byTooltip('Travel'), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();

      expect(repository.added.single.icon, 'plane');
    });
  });

  group('the colour picker', () {
    testWidgets('offers the validated palette and saves the chosen hex', (
      tester,
    ) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Streaming');
      await tester.tap(find.byTooltip('Colour #00897b'), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();

      expect(repository.added.single.colorHex, '#00897b');
    });
  });

  group('deleting', () {
    testWidgets('asks before doing something irreversible', (tester) async {
      await open(tester, initial: existingCategory());

      await tester.tap(find.text('Delete category'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this category?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleted, isEmpty);
    });

    testWidgets('removes a category nothing depends on', (tester) async {
      repository.usage = 0;
      repository.children = 0;
      await open(tester, initial: existingCategory());

      await tester.tap(find.text('Delete category'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.deleted, [4]);
    });

    testWidgets('refuses once it is used, and says how many', (tester) async {
      // DeleteCategory owns this sentence.
      repository.usage = 3;
      await open(tester, initial: existingCategory());

      await tester.tap(find.text('Delete category'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('used by 3 transactions'), findsOneWidget);
      expect(repository.deleted, isEmpty);
    });

    testWidgets('is not offered on a category that has never been saved', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Delete category'), findsNothing);
    });
  });
}
