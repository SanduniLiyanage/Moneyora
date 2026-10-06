/// The left panel of the home screen: which account and which days the
/// figures are for. FR-RPT-002, FR-RPT-003.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/account_icons.dart';
import '../../../../core/widgets/side_panel.dart';
import '../../domain/entities/period_selection.dart';
import '../providers/analytics_providers.dart';
import 'account_filter.dart';
import 'interval_picker.dart';
import 'period_selector.dart';

/// The earliest date the panel's pickers offer, as everywhere else.
final DateTime _pickerFloor = DateTime(2000);

/// Every account and every period, one tap each.
///
/// Opened from the filter icon at the top left of home: a side panel
/// rather than rows of chips over the chart, which on a small phone pushed
/// the chart itself below the fold. Each choice closes the panel, so what
/// the person sees next is its result. Composed into home by
/// `core/router/app_router.dart`, because `features/home/` may not import
/// this feature.
class FilterPanel extends ConsumerWidget {
  /// Creates the panel.
  const FilterPanel({super.key});

  static const List<(String, IconData, AnalyticsPeriod)> _periods = [
    ('Day', Icons.today_outlined, AnalyticsPeriod.day),
    ('Week', Icons.view_week_outlined, AnalyticsPeriod.week),
    ('Month', Icons.calendar_view_month_outlined, AnalyticsPeriod.month),
    ('Year', Icons.calendar_today_outlined, AnalyticsPeriod.year),
    ('All', Icons.all_inclusive, AnalyticsPeriod.all),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(analyticsPeriodProvider);
    final range = ref.watch(analyticsRangeProvider);
    final chosen = ref.watch(analyticsAccountFilterProvider);
    final accounts = ref.watch(accountOptionsProvider).valueOrNull ?? const [];

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                periodLabel(selection, range),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const _Heading('Account'),
            _Choice(
              icon: Icons.account_balance_wallet_outlined,
              label: allAccountsLabel,
              // An account archived or deleted under the filter reads as All
              // accounts, as the dropdown it replaces read it.
              selected: !accounts.any((a) => a.id == chosen),
              onTap: () => _account(context, ref, null),
            ),
            for (final account in accounts)
              _Choice(
                icon: accountIconFor(account.icon),
                label: account.name,
                selected: account.id == chosen,
                onTap: () => _account(context, ref, account.id),
              ),
            const Divider(),
            const _Heading('Period'),
            for (final (label, icon, period) in _periods)
              _Choice(
                icon: icon,
                label: label,
                selected: selection.period == period,
                onTap: () => _period(context, ref, period),
              ),
            _Choice(
              icon: Icons.date_range_outlined,
              label: 'Interval',
              selected: selection.period == AnalyticsPeriod.custom,
              onTap: () => _interval(context, ref, selection),
            ),
            _Choice(
              icon: Icons.event_outlined,
              label: 'Choose date',
              selected: false,
              onTap: () => _date(context, ref, selection),
            ),
          ],
        ),
      ),
    );
  }

  void _account(BuildContext context, WidgetRef ref, int? id) {
    ref.read(analyticsAccountFilterProvider.notifier).state = id;
    closeSidePanel(context);
  }

  void _period(BuildContext context, WidgetRef ref, AnalyticsPeriod period) {
    ref
        .read(analyticsPeriodProvider.notifier)
        .update((it) => it.withPeriod(period));
    closeSidePanel(context);
  }

  /// FR-RPT-002's Custom Interval. Cancelling leaves everything as it was
  /// and the panel open, rather than a Custom period with no days behind it.
  Future<void> _interval(
    BuildContext context,
    WidgetRef ref,
    PeriodSelection selection,
  ) async {
    final existing = selection.customRange;
    final picked = await showIntervalPicker(
      context,
      initial: existing,
      first: _pickerFloor,
      last: DateTime.now(),
    );
    if (picked == null || !context.mounted) return;
    ref
        .read(analyticsPeriodProvider.notifier)
        .update((it) => it.withCustomRange(picked));
    closeSidePanel(context);
  }

  /// FR-RPT-002's Choose Date: the chosen period around the chosen day —
  /// the month a date in March falls in, with Month selected. All and an
  /// interval are about no particular day, so for them it shows the day.
  Future<void> _date(
    BuildContext context,
    WidgetRef ref,
    PeriodSelection selection,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selection.anchor.isAfter(now) ? now : selection.anchor,
      firstDate: _pickerFloor,
      // No future dates, because no transaction can carry one.
      lastDate: now,
    );
    if (picked == null || !context.mounted) return;
    ref.read(analyticsPeriodProvider.notifier).update((it) {
      final period = switch (it.period) {
        AnalyticsPeriod.all || AnalyticsPeriod.custom => AnalyticsPeriod.day,
        final anchored => anchored,
      };
      return it.withPeriod(period).withAnchor(picked);
    });
    closeSidePanel(context);
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    selected: selected,
    trailing: selected ? const Icon(Icons.check) : null,
    onTap: onTap,
  );
}
