import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/category_palette.dart';
import '../../../../core/widgets/category_icons.dart';
import '../../domain/entities/category.dart';
import '../../domain/usecases/add_category.dart';
import '../providers/category_providers.dart';

/// Creating and editing a category. FR-EXP-004, FR-EXP-005.
///
/// One screen for both, the same reasoning `AccountFormPage` gives: a create
/// and an edit are the same fields, and a user thinks of it as "the
/// category". [initial] being null is what makes it a new one.
///
/// Every rule enforced here is [AddCategory.validate] and
/// [AddCategory.validateParent], **called** rather than restated — so a
/// problem appears next to the field that caused it as the user types, and the
/// use case's own sentence is what shows, never a second copy of it that can
/// drift from the first.
class CategoryFormPage extends ConsumerStatefulWidget {
  /// Creates the form, editing [initial] when one is given.
  ///
  /// [initialType] sets which side of the ledger a *new* category starts on —
  /// the category list's two tabs hand back whichever one was open, so
  /// pressing Add on the Income tab does not open an Expense form. Ignored
  /// once [initial] is given, since an existing category already has a type.
  const CategoryFormPage({
    super.key,
    this.initial,
    this.initialType = CategoryType.expense,
  });

  /// The category being edited, or null when creating one.
  final Category? initial;

  /// The type a new category starts as. See the constructor doc.
  final CategoryType initialType;

  @override
  ConsumerState<CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends ConsumerState<CategoryFormPage> {
  late final TextEditingController _name;

  late CategoryType _type;
  late String _iconKey;
  late String _colorHex;
  int? _parentId;

  /// Set once the user has tried to save, so the form does not shout about an
  /// empty name field before they have typed in it.
  bool _submitted = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;

    _name = TextEditingController(text: initial?.name ?? '');
    _type = initial?.type ?? widget.initialType;
    _iconKey = initial?.icon ?? defaultCategoryIconKey;
    _colorHex = initial?.colorHex ?? defaultCategoryColorHex;
    _parentId = initial?.parentId;

    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The category as the form currently describes it.
  Category _build() => Category(
    id: widget.initial?.id,
    name: _name.text.trim(),
    icon: _iconKey,
    colorHex: _colorHex,
    type: _type,
    parentId: _parentId,
    isDefault: widget.initial?.isDefault ?? false,
    sortOrder: widget.initial?.sortOrder ?? 0,
  );

  /// The use case's own verdict on the form as it stands.
  ///
  /// Only the part of validation that needs no repository lookup —
  /// [AddCategory.validateParent] checks the parent's own state, which this
  /// form already has from [categoriesProvider] rather than fetching again.
  ValidationFailure? get _problem {
    final failure = AddCategory.validate(_build());
    if (failure != null) return failure;

    final parentId = _parentId;
    if (parentId == null) return null;

    final parents = ref.read(categoriesProvider(_type)).valueOrNull ?? [];
    Category? parent;
    for (final candidate in parents) {
      if (candidate.id == parentId) {
        parent = candidate;
        break;
      }
    }
    return AddCategory.validateParent(parent, _build());
  }

  /// The message for [field], once the user has tried to save.
  String? _errorFor(String field) {
    if (!_submitted) return null;
    final problem = _problem;
    return problem != null && problem.field == field ? problem.message : null;
  }

  /// Switches the category's side of the ledger.
  ///
  /// A parent chosen under the old type cannot be one under the new type —
  /// [AddCategory.validateParent] refuses a parent of the wrong type — so it
  /// is cleared rather than left to surface as a refusal the user did not
  /// expect from flipping a toggle.
  void _setType(CategoryType next) {
    setState(() {
      _type = next;
      _parentId = null;
    });
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    // Let the use case be the one that refuses. Checking here first only
    // avoids a pointless round trip; the message shown is still its message.
    if (_problem != null) return;

    final saved = await ref
        .read(saveCategoryControllerProvider.notifier)
        .save(_build());

    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      return;
    }

    final error = ref.read(saveCategoryControllerProvider).error;
    if (error is Failure) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Permanently removes the category. FR-EXP-004.
  ///
  /// Asks first, the same reasoning `AccountFormPage._delete` gives: this is
  /// the one action here that cannot be undone. `DeleteCategory` refuses
  /// anyway once something depends on it, naming what and how many.
  Future<void> _delete() async {
    final id = widget.initial?.id;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this category?'),
        content: Text(
          'This removes ${widget.initial!.name} for good. A category with '
          'transactions or sub-categories cannot be deleted — move or remove '
          'those first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final failure = await ref
        .read(deleteCategoryControllerProvider.notifier)
        .call(id);

    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saving = ref.watch(saveCategoryControllerProvider).isLoading;
    final deleting = ref.watch(deleteCategoryControllerProvider).isLoading;

    // Only top-level categories of the same type are offered as a parent:
    // FR-EXP-005's two-level cap means a child cannot itself be a parent, and
    // a category cannot be its own parent either.
    final parentOptions = ref
        .watch(categoriesProvider(_type))
        .valueOrNull
        ?.where((c) => !c.isChild && c.id != widget.initial?.id)
        .toList();

    // What the dropdown can actually show right now. `_parentId` is the
    // field's source of truth and is never rewritten here — this only
    // decides the widget's displayed value, which must be one of its own
    // items or `DropdownButtonFormField` asserts. Falling back to "None"
    // covers two ordinary moments rather than a corrupt one: the list is
    // still loading on the first frame, or the saved parent id belongs to a
    // category this render does not have in hand yet.
    final displayedParentId =
        parentOptions != null && parentOptions.any((c) => c.id == _parentId)
        ? _parentId
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit category' : 'New category'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'Groceries, Streaming',
                border: const OutlineInputBorder(),
                errorText: _errorFor('name'),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<CategoryType>(
              segments: const [
                ButtonSegment(
                  value: CategoryType.expense,
                  label: Text('Expense'),
                ),
                ButtonSegment(
                  value: CategoryType.income,
                  label: Text('Income'),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (next) => _setType(next.first),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              // Rekeyed whenever the displayed value changes for a reason
              // other than the user picking one — the list finishing its
              // first (async) load being the main case. `initialValue` only
              // seeds the field's internal state once, at creation, and a
              // fresh key is what makes that seed run again once the real
              // parent becomes a valid choice.
              key: ValueKey('parent-${_type.name}-$displayedParentId'),
              initialValue: displayedParentId,
              decoration: InputDecoration(
                labelText: 'Parent category',
                border: const OutlineInputBorder(),
                errorText: _errorFor('parentId'),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                for (final parent in parentOptions ?? const <Category>[])
                  DropdownMenuItem(value: parent.id, child: Text(parent.name)),
              ],
              onChanged: (next) => setState(() => _parentId = next),
            ),
            const SizedBox(height: 16),
            Text('Icon', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _IconPicker(
              selectedKey: _iconKey,
              onSelected: (key) => setState(() => _iconKey = key),
            ),
            const SizedBox(height: 16),
            Text('Colour', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _ColorPicker(
              selectedHex: _colorHex,
              onSelected: (hex) => setState(() => _colorHex = hex),
            ),
            const SizedBox(height: 24),
            FilledButton(
              // Enabled even when invalid: the point of pressing Save is to
              // find out what is wrong, and a greyed button with no message
              // beside it is a dead end.
              onPressed: saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save changes' : 'Add category'),
            ),
            // Only a category that exists can be deleted. On a new one there
            // is nothing to act on, and a greyed control would be furniture
            // rather than information.
            if (_isEditing) ...[
              const Divider(height: 40),
              TextButton.icon(
                onPressed: deleting ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                label: const Text('Delete category'),
              ),
              const SizedBox(height: 8),
              Text(
                // FR-EXP-004. Stating the limit up front rather than letting
                // the refusal be the first thing heard of it — DeleteCategory
                // will refuse either way, but a rule discovered by being told
                // "no" reads as the app being awkward.
                'Only possible while nothing is filed under it — no '
                'transactions, and no sub-categories.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The grid of built-in icons. FR-EXP-004.
class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selectedKey, required this.onSelected});

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 96,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: categoryIcons.length,
        itemBuilder: (context, index) {
          final entry = categoryIcons[index];
          final selected = entry.key == selectedKey;

          return Tooltip(
            message: entry.label,
            child: InkWell(
              onTap: () => onSelected(entry.key),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: selected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  border: selected
                      ? Border.all(color: theme.colorScheme.primary, width: 2)
                      : null,
                ),
                child: Semantics(
                  label: entry.label,
                  selected: selected,
                  button: true,
                  child: Icon(
                    entry.icon,
                    color: selected ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The grid of validated colour swatches. FR-EXP-004.
///
/// Drawn from [categoryPalette] rather than a colour wheel: `default_seed
/// .dart`'s doc comment is explicit that these fifteen hues were the ones
/// that survived a categorical-distinctness and colour-vision-deficiency
/// check, and an open-ended picker would let a user choose a colour nobody
/// verified against that requirement.
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selectedHex, required this.onSelected});

  final String selectedHex;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final swatch in categoryPalette)
          _Swatch(
            hex: swatch.light,
            color: colorFromHex(
              brightness == Brightness.dark ? swatch.dark : swatch.light,
            )!,
            selected: swatch.light == selectedHex,
            onTap: () => onSelected(swatch.light),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.hex,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Colour $hex',
      child: Semantics(
        label: 'Colour $hex',
        selected: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: theme.colorScheme.onSurface, width: 3)
                  : null,
            ),
            child: selected
                ? Icon(Icons.check, color: theme.colorScheme.surface, size: 20)
                : null,
          ),
        ),
      ),
    );
  }
}
