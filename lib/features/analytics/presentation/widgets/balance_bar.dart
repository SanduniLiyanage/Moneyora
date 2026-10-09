import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/period_summary.dart';
import '../providers/analytics_providers.dart';
import 'account_filter.dart';
import 'period_selector.dart';

/// Income less expenses over the chosen period and account, and the way to
/// change either. FR-RPT-002, FR-RPT-003, FR-RPT-006, FR-TRF-004.
///
/// The same bar on the home screen and on the transaction list, reading the
/// one selection both follow, so the balance, the charts and the rows below
/// always describe the same days and the same account. Green when more came
/// in than went out; red otherwise, a balance of nothing included — the
/// owner's rule, since nothing saved is not a result to show as good.
/// With one account chosen, transfers move it too: cash drawn from a card is
/// money gone from the card and money arrived in cash, and someone looking
/// at either expects to see it. Across every account each transfer's legs
/// cancel, so there they change nothing. They are still never income or
/// spending (E-02): the summary card, the charts and the plan never see them.
///
/// On home, tapping it opens the transaction list for the same period and
/// account ([opensList]): the balance is what the rows add up to. On the list,
/// where there is no side panel, it opens the period and account choices.
class BalanceBar extends ConsumerWidget {
  /// Creates the bar.
  const BalanceBar({super.key, this.opensList = false});

  /// Whether a tap opens the transaction list rather than the choices.
  final bool opensList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final selection = ref.watch(analyticsPeriodProvider);
    final range = ref.watch(analyticsRangeProvider);
    final accountId = ref.watch(analyticsAccountFilterProvider);
    final accounts = ref.watch(accountOptionsProvider).valueOrNull;
    final summary = ref.watch(periodSummaryProvider);

    final accountName = switch (accountId) {
      null => 'All accounts',
      final id =>
        accounts?.where((a) => a.id == id).firstOrNull?.name ?? 'All accounts',
    };

    final (amount, tint) = switch (summary) {
      AsyncData(value: PeriodSummary(:final balanceCents)) => (
        balanceCents > 0
            ? '+${formatCents(balanceCents)}'
            : balanceCents < 0
            ? '−${formatCents(-balanceCents)}'
            : formatCents(0),
        balanceCents > 0 ? colors.income : colors.expense,
      ),
      AsyncError() => ('—', theme.colorScheme.onSurfaceVariant),
      _ => ('…', theme.colorScheme.onSurfaceVariant),
    };
    final detail = switch (summary) {
      // What came into and went out of the account, transfers included, so
      // in less out is the balance above it — with the opening balance
      // first when the account was opened in the period (E-41).
      AsyncData(:final value) =>
        '${_opening(value.openingBalanceCents)}'
            'In ${formatCents(value.incomeCents + value.transferInCents)} · '
            'out ${formatCents(value.expenseCents + value.transferOutCents)}',
      AsyncError(:final error) =>
        error is Failure ? error.message : 'The balance could not be read.',
      _ => null,
    };

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: opensList
            // push, so the list stacks on home and back returns here.
            ? () => context.push(Routes.transactions)
            : () => showBalanceFilters(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${periodLabel(selection, range)} · $accountName',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        // Both sides give way at the largest font on a
                        // small phone: the label fades, the amount shrinks.
                        Flexible(
                          child: Text(
                            'Balance',
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              amount,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: tint,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (detail != null)
                      Text(detail, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                opensList ? Icons.chevron_right : Icons.tune,
                color: theme.colorScheme.primary,
                semanticLabel: opensList
                    ? 'Open the transactions'
                    : 'Change period or account',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Opening Rs5,000.00 · " before the in and out, or nothing when no
/// account counted was opened in the period.
String _opening(int cents) => switch (cents) {
  0 => '',
  < 0 => 'Opening −${formatCents(-cents)} · ',
  _ => 'Opening ${formatCents(cents)} · ',
};

/// The period and account choices, over whatever screen asked. Changes
/// apply as they are made; the balance and everything under it follow.
Future<void> showBalanceFilters(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Period', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const PeriodSelector(),
              const SizedBox(height: 16),
              Text('Account', style: Theme.of(context).textTheme.titleMedium),
              const AccountFilter(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
