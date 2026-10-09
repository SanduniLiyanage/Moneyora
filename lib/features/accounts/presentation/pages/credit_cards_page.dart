import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' show Left, Right;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/account_icons.dart';
import '../../../../injection.dart' show clockProvider;
import '../../domain/entities/account.dart';
import '../../domain/entities/credit_card_summary.dart';
import '../../domain/usecases/plan_card_payoff.dart';
import '../providers/account_providers.dart';

/// Every credit card: what is owed, what is left to spend, when the
/// statement and the payment fall, and what owing costs. FR-ACC-009, E-43.
///
/// A card is an account of the Credit card type; its terms are entered on
/// the account's form, which the pencil on each card opens. A figure whose
/// term was not entered is not shown, and the card says what to add.
class CreditCardsPage extends ConsumerWidget {
  /// Creates the screen.
  const CreditCardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider(false));
    final today = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Credit cards')),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Empty(
          title: 'Could not read your accounts',
          body: error is Failure ? error.message : 'Please try again.',
        ),
        data: (all) {
          final cards = [
            for (final a in all)
              if (a.type == AccountType.creditCard) a,
          ];
          if (cards.isEmpty) {
            // E-22: what belongs here, and how to put it there.
            return _Empty(
              title: 'No credit cards yet',
              body:
                  'Add an account of the Credit card type, with its limit, '
                  'due day and interest rate, and it is shown here.',
              action: FilledButton.icon(
                onPressed: () => context.push(
                  Routes.accountForm,
                  extra: AccountType.creditCard,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add a card'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final card in cards)
                _CardSummary(key: ValueKey(card.id), card: card, today: today),
            ],
          );
        },
      ),
    );
  }
}

class _CardSummary extends StatelessWidget {
  const _CardSummary({required this.card, required this.today, super.key});

  final Account card;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final summary = CreditCardSummary.of(card, today: today);
    final currency = CurrencyFormat.forCode(card.currency);
    String money(int cents) => formatCents(cents, currency: currency);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );
    final day = DateFormat('d MMM');

    final limit = summary.limitCents;
    final available = summary.availableCents;
    final share = summary.utilisationPercent;
    final due = summary.nextDue;
    final statement = summary.nextStatement;
    final apr = summary.aprBasisPoints;
    final interest = summary.monthlyInterestCents;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(accountIconFor(card.icon)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    card.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit card',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      context.push(Routes.accountForm, extra: card),
                ),
              ],
            ),
            Text(
              limit == null
                  ? 'Owed ${money(summary.owedCents)}'
                  : 'Owed ${money(summary.owedCents)} of ${money(limit)}',
              style: theme.textTheme.titleLarge?.copyWith(
                color: summary.owedCents > 0 ? colors.expense : null,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (share != null) ...[
              const SizedBox(height: 8),
              Semantics(
                label: '$share% of the limit used',
                child: LinearProgressIndicator(
                  value: (share / 100).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  color: share >= 80 ? colors.expense : colors.income,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                available! < 0
                    ? '${money(-available)} over the limit'
                    : '${money(available)} left to spend · $share% used',
                style: available < 0
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      )
                    : muted,
              ),
            ],
            if (statement != null || due != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (statement != null) 'Statement ${day.format(statement)}',
                  if (due != null)
                    'Payment due ${day.format(due)} '
                        '(${_inDays(summary.daysUntilDue(today)!)})',
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
            Text(switch ((apr, interest)) {
              (final rate?, final cost?) when summary.owedCents > 0 =>
                'At ${_percent(rate)} a year, about ${money(cost)} interest '
                    'a month on what is owed, if it is not paid in full by '
                    'the due date.',
              (final rate?, _) =>
                'Nothing owed, so no interest. The rate is ${_percent(rate)} '
                    'a year.',
              _ =>
                'Add the interest rate on the card to see what owing on '
                    'it costs.',
            }, style: muted),
            if (switch ((limit, due)) {
                  (null, null) =>
                    'Add the credit limit and the payment due day to see what '
                        'is left to spend and when payment is due.',
                  (null, _) =>
                    'Add the credit limit to see what is left to spend.',
                  (_, null) => 'Add the payment due day to see when it is due.',
                  _ => null,
                }
                case final missing?)
              Text(missing, style: muted),
            if (apr != null && summary.owedCents > 0)
              _PayoffCalculator(
                owedCents: summary.owedCents,
                aprBasisPoints: apr,
                money: money,
              ),
          ],
        ),
      ),
    );
  }

  static String _inDays(int days) => switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    _ => 'in $days days',
  };

  static String _percent(int basisPoints) =>
      '${formatCents(basisPoints, showSymbol: false)}%';
}

/// "If I pay this much each month": how long, and how much of it is
/// interest. An estimate, and it says so. FR-ACC-009.
class _PayoffCalculator extends StatefulWidget {
  const _PayoffCalculator({
    required this.owedCents,
    required this.aprBasisPoints,
    required this.money,
  });

  final int owedCents;
  final int aprBasisPoints;
  final String Function(int cents) money;

  @override
  State<_PayoffCalculator> createState() => _PayoffCalculatorState();
}

class _PayoffCalculatorState extends State<_PayoffCalculator> {
  final _payment = TextEditingController();

  @override
  void dispose() {
    _payment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cents = parseToCents(_payment.text);
    final answer = cents == null
        ? null
        : switch (PlanCardPayoff.plan(
            PayoffRequest(
              owedCents: widget.owedCents,
              aprBasisPoints: widget.aprBasisPoints,
              monthlyPaymentCents: cents,
            ),
          )) {
            Right(value: final plan) =>
              'Paid off in ${plan.months} '
                  '${plan.months == 1 ? 'month' : 'months'}, with about '
                  '${widget.money(plan.totalInterestCents)} of interest. '
                  'An estimate: the card charges interest its own way.',
            Left(value: final failure) => failure.message,
          };

    return Padding(
      padding: const EdgeInsets.only(top: 12, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _payment,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'If I pay each month',
              hintText: '0.00',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (answer != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(answer, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body, this.action});

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.credit_card, size: 48, color: muted),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
