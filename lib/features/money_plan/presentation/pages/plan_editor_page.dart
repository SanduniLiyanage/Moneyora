import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/category_reader.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/scale_down_text.dart';
import '../../domain/entities/plan_line.dart';
import '../../domain/entities/plan_period.dart';
import '../../domain/usecases/save_built_plan.dart';
import '../providers/money_plan_providers.dart';
import '../widgets/plan_labels.dart';
import '../widgets/plan_name_dialog.dart';

/// What the plan editor starts from. E-39.
class PlanEditorArgs {
  /// Starts from [lines]; with none, from every expense category, empty.
  const PlanEditorArgs({
    required this.period,
    this.lines = const [],
    this.suggestedTotalCents,
  });

  /// The days the plan covers, chosen in the wizard.
  final PlanPeriod period;

  /// The generator's lines, to edit; empty to build by hand.
  final List<PlanLine> lines;

  /// What the generator's plan added up to, for comparison. Null when the
  /// plan is being built by hand.
  final int? suggestedTotalCents;

  /// True when the user is building the plan rather than editing one.
  bool get isBuiltByHand => lines.isEmpty;
}

/// A plan, category by category, with the figures the user types.
/// FR-PLN-011, E-39.
///
/// Two ways in. With too little history for the generator, the user builds
/// the plan here from their expense categories, leaving empty the ones they
/// do not want to budget. With a generated plan, the user edits its figures
/// before saving: changes, additions, removals. Either way the total is what
/// the lines add up to — nothing is recalculated behind a figure the user
/// typed; the active plan's adjust (FR-PLN-011) is where a total is held.
class PlanEditorPage extends ConsumerStatefulWidget {
  /// Creates the editor for [args].
  const PlanEditorPage({required this.args, super.key});

  /// Where it starts from.
  final PlanEditorArgs args;

  @override
  ConsumerState<PlanEditorPage> createState() => _PlanEditorPageState();
}

class _Row {
  _Row(this.line)
    : controller = TextEditingController(
        text: line.amountCents > 0 ? _editable(line.amountCents) : '',
      );

  final PlanLine line;
  final TextEditingController controller;

  /// What the field holds: null when it is empty, -1 when it is not money.
  int? get typed {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return parseToCents(text) ?? -1;
  }

  PlanLine get current => line.withAmount(switch (typed) {
    null => 0,
    final cents => cents,
  });

  /// A whole figure without its ".00", the way a person would type it.
  static String _editable(int cents) =>
      cents % 100 == 0 ? '${cents ~/ 100}' : formatCentsPlain(cents);
}

class _PlanEditorPageState extends ConsumerState<PlanEditorPage> {
  final List<_Row> _rows = [];
  bool _seeded = false;
  bool _dirty = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    if (!widget.args.isBuiltByHand) {
      _rows.addAll(widget.args.lines.map(_track));
      _seeded = true;
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.controller.dispose();
    }
    super.dispose();
  }

  _Row _track(PlanLine line) {
    final row = _Row(line);
    row.controller.addListener(() => setState(() => _dirty = true));
    return row;
  }

  /// Building by hand starts from every expense category, once they load.
  void _seed(List<CategoryOption> categories) {
    if (_seeded) return;
    _seeded = true;
    _rows.addAll([
      for (final c in categories)
        _track(
          PlanLine(categoryId: c.id, categoryName: c.name, amountCents: 0),
        ),
    ]);
  }

  List<PlanLine> get _lines => [for (final r in _rows) r.current];

  int get _totalCents => _rows.fold(
    0,
    (sum, r) =>
        sum +
        switch (r.typed) {
          final int c when c > 0 => c,
          _ => 0,
        },
  );

  String? _problem() {
    if (_rows.any((r) => r.typed == -1)) {
      return 'One of the amounts is not a number.';
    }
    return SaveBuiltPlan.validate(
      BuiltPlanRequest(
        // The name is asked for after this check passes.
        name: 'x',
        period: widget.args.period,
        lines: _lines,
      ),
    )?.message;
  }

  void _remove(_Row row) {
    setState(() {
      _rows.remove(row);
      _dirty = true;
    });
    // After the frame: the field may still be focused as it goes.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => row.controller.dispose(),
    );
  }

  Future<void> _add(List<CategoryOption> categories) async {
    final inPlan = {for (final r in _rows) r.line.categoryId};
    final left = [
      for (final c in categories)
        if (!inPlan.contains(c.id)) c,
    ];
    final picked = await showModalBottomSheet<CategoryOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: left.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Every expense category is already in the plan.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Add a category',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final c in left)
                      ListTile(
                        title: Text(c.name),
                        onTap: () => Navigator.of(context).pop(c),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _rows.add(
        _track(
          PlanLine(
            categoryId: picked.id,
            categoryName: picked.name,
            amountCents: 0,
          ),
        ),
      );
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final problem = _problem();
    if (problem != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final choice = await PlanNameDialog.show(
      context,
      initial: planPeriodLabel(widget.args.period),
    );
    if (choice == null || !mounted) return;

    final id = await ref
        .read(saveBuiltPlanControllerProvider.notifier)
        .save(
          BuiltPlanRequest(
            name: choice.name,
            period: widget.args.period,
            lines: _lines,
            activate: choice.activate,
          ),
        );
    if (!mounted) return;

    if (id != null) {
      _dirty = false;
      // As the review screen: home underneath, the plan on top.
      context.go(Routes.home);
      unawaited(
        context.push(choice.activate ? Routes.activePlan : Routes.plans),
      );
      return;
    }
    final error = ref.read(saveBuiltPlanControllerProvider).error;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            error is Failure ? error.message : 'The plan could not be saved.',
          ),
        ),
      );
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text('The amounts you typed will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(planCategoriesProvider);
    final all = categories.valueOrNull;
    if (all != null && !_seeded) _seed(all);
    final saving = ref.watch(saveBuiltPlanControllerProvider).isLoading;
    final args = widget.args;
    final period = args.period;
    final total = _totalCents;
    final problem = _submitted ? _problem() : null;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!await _confirmLeave() || !context.mounted) return;
        // Rebuilt first, so the pop meets canPop: true rather than this
        // guard again.
        setState(() => _dirty = false);
        await WidgetsBinding.instance.endOfFrame;
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            args.isBuiltByHand ? 'Build your plan' : 'Edit your plan',
          ),
        ),
        body: !_seeded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _TotalCard(
                    period: period,
                    totalCents: total,
                    suggestedCents: args.suggestedTotalCents,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    args.isBuiltByHand
                        ? 'Type a budget for each category you want to plan. '
                              'Leave the rest empty: they stay out of the plan.'
                        : 'Change any amount, remove a category, or add one. '
                              'The total follows what you type.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  for (final row in _rows)
                    Padding(
                      key: ObjectKey(row),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _LineField(
                        row: row,
                        days: period.days,
                        onRemove: () => _remove(row),
                      ),
                    ),
                  if (_rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No categories yet. Add one to start.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: all == null ? null : () => _add(all),
                      icon: const Icon(Icons.add),
                      label: const Text('Add a category'),
                    ),
                  ),
                  if (problem != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      problem,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: saving || !_seeded ? null : _save,
              child: Text(saving ? 'Saving…' : 'Save plan'),
            ),
          ),
        ),
      ),
    );
  }
}

/// The plan's period and running total, against the suggestion if any.
class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.period,
    required this.totalCents,
    required this.suggestedCents,
  });

  final PlanPeriod period;
  final int totalCents;
  final int? suggestedCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggested = suggestedCents;
    final difference = suggested == null ? 0 : totalCents - suggested;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(planPeriodLabel(period), style: theme.textTheme.titleMedium),
            Text(
              '${period.days} day${period.days == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Total', style: theme.textTheme.titleMedium),
                ),
                const SizedBox(width: 8),
                ScaleDownText(
                  formatCents(totalCents),
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            if (period.days > 0 && totalCents > 0)
              Text(
                '${formatCents(totalCents ~/ period.days)} a day',
                style: theme.textTheme.bodySmall,
              ),
            if (suggested != null) ...[
              const SizedBox(height: 4),
              Text(switch (difference) {
                0 => 'The same as suggested.',
                > 0 =>
                  '${formatCents(difference)} more than the suggested '
                      '${formatCents(suggested)}.',
                _ =>
                  '${formatCents(-difference)} less than the suggested '
                      '${formatCents(suggested)}.',
              }, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// One category's amount, full width so a long name and a large font fit.
class _LineField extends StatelessWidget {
  const _LineField({
    required this.row,
    required this.days,
    required this.onRemove,
  });

  final _Row row;
  final int days;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final line = row.line;
    final typed = row.typed;
    final suggestion = line.suggestion;
    final helper = [
      if (typed != null && typed > 0 && days > 0)
        '${formatCents(typed ~/ days)} a day',
      if (suggestion != null && typed != suggestion.amountCents)
        'Suggested ${formatCents(suggestion.amountCents)}',
    ].join(' · ');
    return TextField(
      controller: row.controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: line.categoryName,
        prefixText: 'Rs ',
        hintText: 'Not in the plan',
        helperText: helper.isEmpty ? null : helper,
        errorText: typed == -1 ? 'Type an amount, like 2500' : null,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Remove ${line.categoryName}',
          onPressed: onRemove,
        ),
      ),
    );
  }
}
