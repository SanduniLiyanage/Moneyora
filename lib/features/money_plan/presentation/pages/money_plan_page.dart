import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/ports/calendar_settings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../injection.dart' show calendarSettingsProvider;
import '../../domain/entities/allocation_request.dart';
import '../../domain/entities/budget_mode.dart';
import '../../domain/entities/lookback_window.dart';
import '../../domain/entities/plan_period.dart';
import '../../domain/usecases/allocate_budget.dart';
import '../widgets/plan_labels.dart';

/// The wizard's first step: which days to plan, and how to decide the
/// total. FR-PLN-001, FR-PLN-002, FR-PLN-008.
///
/// Builds an [AllocationRequest] and hands it to the review screen; nothing
/// is computed or written here. The lookback is FR-PLN-003's setting
/// (FR-SET-012), read from the stored row and stated on screen with where
/// to change it — not changed here, because two places to set one thing is
/// one too many, and Settings is where the SRS puts it. Weeks and months
/// are cut where FR-SET-004 says, so a plan and the analytics behind it
/// agree on what a month is.
class MoneyPlanPage extends ConsumerStatefulWidget {
  /// Creates the screen. [now] is the clock, injectable for tests.
  const MoneyPlanPage({super.key, this.now});

  /// The clock. `DateTime.now()` when null.
  final DateTime? now;

  @override
  ConsumerState<MoneyPlanPage> createState() => _MoneyPlanPageState();
}

enum _Mode { history, total, suggested }

class _MoneyPlanPageState extends ConsumerState<MoneyPlanPage> {
  late final DateTime _now;

  /// The stored calendar, or the schema's defaults until it is known.
  CalendarSettings get _calendar =>
      ref.watch(calendarSettingsProvider).asData?.value ??
      CalendarSettings.defaults;
  late DateTime _anchor;
  DateTime? _rangeEnd;
  PlanPeriodType _shape = PlanPeriodType.month;
  _Mode _mode = _Mode.history;

  final TextEditingController _days = TextEditingController(text: '15');
  final TextEditingController _total = TextEditingController();
  final TextEditingController _savings = TextEditingController(text: '10');

  /// Whether the user has typed a savings figure, which then outranks the
  /// stored target arriving late.
  bool _savingsTyped = false;

  /// Set once the user has tried to continue, so the screen does not object
  /// to an empty total before they have typed one.
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _now = widget.now ?? DateTime.now();
    // A plan is for what comes next: the month after this one, from its
    // first day.
    _anchor = DateTime(_now.year, _now.month + 1);
    for (final c in [_days, _total, _savings]) {
      c.addListener(() => setState(() {}));
    }
    // FR-SET-008: the savings figure starts from the stored target, set
    // once in Settings, rather than from a number this screen made up. 10%
    // stays the suggestion when none is set.
    ref.listenManual(calendarSettingsProvider, (_, next) {
      final stored = next.asData?.value;
      if (stored == null || !stored.hasSavingsTarget || _savingsTyped) return;
      final pct = stored.savingsTargetPct;
      _savings.text = pct == pct.roundToDouble() ? '${pct.round()}' : '$pct';
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _days.dispose();
    _total.dispose();
    _savings.dispose();
    super.dispose();
  }

  PlanPeriod _period() => switch (_shape) {
    PlanPeriodType.day => PlanPeriod.day(_anchor),
    PlanPeriodType.week => PlanPeriod.week(
      _anchor,
      firstWeekday: _calendar.firstWeekday,
    ),
    PlanPeriodType.month => PlanPeriod.monthOf(
      _anchor,
      firstDay: _calendar.firstDayOfMonth,
    ),
    PlanPeriodType.year => PlanPeriod.year(_anchor.year),
    PlanPeriodType.customDays => PlanPeriod.days(
      _anchor,
      int.tryParse(_days.text.trim()) ?? 0,
    ),
    PlanPeriodType.customRange => PlanPeriod(
      from: _anchor,
      to: _rangeEnd ?? _anchor,
    ),
  };

  BudgetMode _budgetMode() => switch (_mode) {
    _Mode.history => const BudgetMode.unconstrained(),
    _Mode.total => BudgetMode.total(parseToCents(_total.text) ?? -1),
    _Mode.suggested => BudgetMode.suggested(
      savingsTargetPct: double.tryParse(_savings.text.trim()) ?? -1,
    ),
  };

  AllocationRequest _request() => AllocationRequest(
    period: _period(),
    lookback: LookbackWindow.before(_now, months: _calendar.planAnalysisMonths),
    mode: _budgetMode(),
  );

  /// The screen's own checks before the use case's: an empty field is a
  /// different message from an out-of-range one.
  String? _fieldProblem() {
    if (_shape == PlanPeriodType.customDays &&
        (int.tryParse(_days.text.trim()) ?? 0) < 1) {
      return 'Enter at least one day.';
    }
    if (_mode == _Mode.total && parseToCents(_total.text) == null) {
      return 'Enter a total budget.';
    }
    if (_mode == _Mode.suggested &&
        double.tryParse(_savings.text.trim()) == null) {
      return 'Enter a savings target.';
    }
    return null;
  }

  String? _problem() =>
      _fieldProblem() ?? AllocateBudget.validate(_request())?.message;

  Future<void> _pickAnchor() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) setState(() => _anchor = picked);
  }

  Future<void> _pickRangeEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeEnd ?? _anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) setState(() => _rangeEnd = picked);
  }

  void _generate() {
    setState(() => _submitted = true);
    if (_problem() != null) return;
    context.push(Routes.moneyPlanReview, extra: _request());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _submitted ? _problem() : null;
    final period = _period();

    return Scaffold(
      appBar: AppBar(title: const Text('Create Money Plan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Plan for', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final type in PlanPeriodType.values)
                ChoiceChip(
                  label: Text(periodTypeLabel(type)),
                  selected: _shape == type,
                  onSelected: (_) => setState(() => _shape = type),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _DateRow(
            label: switch (_shape) {
              PlanPeriodType.customDays ||
              PlanPeriodType.customRange => 'Starting',
              _ => 'Containing',
            },
            date: _anchor,
            onTap: _pickAnchor,
          ),
          if (_shape == PlanPeriodType.customDays)
            TextField(
              controller: _days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Days'),
            ),
          if (_shape == PlanPeriodType.customRange)
            _DateRow(
              label: 'Ending',
              date: _rangeEnd ?? _anchor,
              onTap: _pickRangeEnd,
            ),
          const SizedBox(height: 4),
          Text(
            period.isInverted
                ? 'The start of the plan is after its end.'
                : '${planPeriodLabel(period)} · ${period.days} '
                      'day${period.days == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Text('Total budget', style: theme.textTheme.titleMedium),
          RadioGroup<_Mode>(
            groupValue: _mode,
            onChanged: (m) => setState(() => _mode = m!),
            child: Column(
              children: [
                const RadioListTile<_Mode>(
                  value: _Mode.history,
                  title: Text('From your spending history'),
                  subtitle: Text('What the plan adds up to'),
                ),
                const RadioListTile<_Mode>(
                  value: _Mode.total,
                  title: Text('Set a total'),
                  subtitle: Text('Shared across categories proportionally'),
                ),
                if (_mode == _Mode.total)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _total,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Total budget',
                        prefixText: 'Rs ',
                      ),
                    ),
                  ),
                const RadioListTile<_Mode>(
                  value: _Mode.suggested,
                  title: Text('Suggest from income'),
                  subtitle: Text('Income, less fixed costs, less savings'),
                ),
                if (_mode == _Mode.suggested)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _savings,
                      onChanged: (_) => _savingsTyped = true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Savings target',
                        suffixText: '% of income',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            // FR-PLN-003, FR-SET-012. Read-only here on purpose: the number
            // is set under Settings and only there.
            _calendar.planAnalysisMonths == 1
                ? 'Based on the last month of spending — change this under '
                      'Settings › Calendar.'
                : 'Based on the last ${_calendar.planAnalysisMonths} months '
                      'of spending — change this under Settings › Calendar.',
            style: theme.textTheme.bodySmall,
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
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _generate,
            child: const Text('Generate plan'),
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.calendar_today_outlined),
    title: Text(label),
    subtitle: Text(DateFormat.yMMMMd().format(date)),
    onTap: onTap,
  );
}
