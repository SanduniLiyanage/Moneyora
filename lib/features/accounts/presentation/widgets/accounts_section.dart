import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/conversion_table.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/account_icons.dart';
import '../../../../core/widgets/scale_down_text.dart';
import '../../../../core/widgets/side_panel.dart';
import '../../../../injection.dart' show conversionTableProvider;
import '../../domain/entities/account.dart';
import '../../domain/entities/account_totals.dart';
import '../providers/account_providers.dart';

/// The accounts and their balances, inside the menu's Accounts item.
/// FR-ACC-003.
///
/// The menu on the right of home opens it in place, the way the reference
/// app does: a row to add a transfer or an account, then each account with
/// its balance, then the total. Composed into the menu by
/// `core/router/app_router.dart` rather than imported by the home screen,
/// because a feature importing another feature is what rule 4 of
/// `scripts/check_architecture.sh` forbids.
///
/// Archived accounts are hidden by default (FR-ACC-004) — that is what
/// archiving is for — and shown behind a toggle, because an account that can
/// be hidden and never seen again cannot be restored.
class AccountsSection extends ConsumerWidget {
  /// Creates the section.
  const AccountsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showArchived = ref.watch(showArchivedAccountsProvider);
    final accounts = ref.watch(accountsProvider(showArchived));
    // The base currency and the user's rates, from the settings feature
    // through its port (FR-ACC-005): the total is meaningless without them,
    // so the section waits for both rather than drawing a figure it would
    // then correct.
    final table = ref.watch(conversionTableProvider);

    return switch ((accounts, table)) {
      (AsyncData(value: final list), AsyncData(value: final rates)) =>
        _Accounts(accounts: list, table: rates, showingArchived: showArchived),
      (AsyncError(:final error), _) ||
      (_, AsyncError(:final error)) => _Problem(error: error),
      _ => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

/// Closes the menu, then opens [route] over home.
///
/// Closed first: pushing over an open panel leaves it open underneath, so
/// coming back lands on a screen with the panel still covering it.
void _open(BuildContext context, String route, {Object? extra}) {
  final router = GoRouter.of(context);
  closeSidePanel(context);
  router.push(route, extra: extra);
}

class _Accounts extends ConsumerWidget {
  const _Accounts({
    required this.accounts,
    required this.table,
    required this.showingArchived,
  });

  final List<Account> accounts;

  /// The base currency and every rate the user has entered.
  final ConversionTable table;

  /// Whether archived accounts are currently included. FR-ACC-004.
  final bool showingArchived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final totals = AccountTotals.from(accounts, table);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AddRow(),
        // E-22 lists the accounts surface as one whose empty state "cannot
        // occur": the seed creates a Cash account and ArchiveAccount refuses
        // to archive the last one. That reasoning holds for the default list
        // and not for this one — turning the archived filter on with nothing
        // archived empties it, which E-22's table does not cover. So there
        // are two empty states here, per its own rule that "nothing yet" and
        // "nothing matching the filter" are different sentences.
        if (accounts.isEmpty)
          _NoAccounts(showingArchived: showingArchived)
        else
          for (final account in accounts)
            _AccountTile(account: account, baseCurrency: table.baseCurrency),
        _Total(totals: totals),
        SwitchListTile(
          value: showingArchived,
          onChanged: (next) =>
              ref.read(showArchivedAccountsProvider.notifier).state = next,
          secondary: const Icon(Icons.archive_outlined),
          title: const Text('Show archived'),
          dense: true,
        ),
        if (totals.hasUnconverted)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              // E-34's fallback, which is E-25's rule kept for the accounts
              // it still applies to: saying what was left out, why, and what
              // would include it, rather than converting at an invented rate
              // or adding dollars to rupees. The number above is then correct
              // rather than approximate.
              totals.unconvertedCount == 1
                  ? 'One account is not counted — it has no exchange rate to '
                        '${totals.baseCurrency} yet. Add one under Settings.'
                  : '${totals.unconvertedCount} accounts are not counted — '
                        'they have no exchange rate to ${totals.baseCurrency} '
                        'yet. Add them under Settings.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
      ],
    );
  }
}

/// The first row: move money between accounts, or add one.
class _AddRow extends StatelessWidget {
  const _AddRow();

  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('Add'),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.swap_horiz),
          tooltip: 'New transfer',
          onPressed: () => _open(context, Routes.transfer),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'New account',
          onPressed: () => _open(context, Routes.accountForm),
        ),
      ],
    ),
  );
}

class _Total extends StatelessWidget {
  const _Total({required this.totals});

  final AccountTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    // The label above the figure rather than beside it: beside, a large
    // balance at the largest font has nowhere to go in a panel.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total balance',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatCents(
              totals.totalCents,
              currency: CurrencyFormat.forCode(totals.baseCurrency),
            ),
            style: theme.textTheme.titleLarge?.copyWith(
              // Owing money overall is worth seeing at a glance, and the
              // income/expense pair is the vocabulary the rest of the app
              // already uses for that.
              color: totals.totalCents < 0 ? colors.expense : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.baseCurrency});

  final Account account;

  /// The currency whose label is noise on a row, because it is assumed.
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final balance = account.currentBalanceCents;

    return ListTile(
      // The account's chosen icon (FR-ACC-006), falling back to its type when
      // the key is one the catalogue does not know — a restored backup, or a
      // row from an older build.
      leading: Icon(
        account.icon.isEmpty
            ? _iconFor(account.type)
            : accountIconFor(account.icon),
      ),
      title: Text(account.name),
      onTap: () => _open(context, Routes.accountForm, extra: account),
      // Two things can want the second line, and archived is the one that
      // changes what the row means — a currency label beside a closed account
      // answers a question nobody is asking.
      //
      // Otherwise the currency, and only when it is not the base: repeating
      // "LKR" on every row on an install that has never seen another
      // currency is noise.
      subtitle: switch (account) {
        Account(isArchived: true) => const Text('Archived'),
        Account(:final currency) when currency.toUpperCase() != baseCurrency =>
          Text(currency.toUpperCase()),
        _ => null,
      },
      // Shrinks rather than taking the row: at the largest font a panel
      // has no room for a full balance beside the name.
      trailing: ScaleDownText(
        formatCents(
          balance,
          currency: CurrencyFormat.forCode(account.currency),
        ),
        maxWidthFactor: 0.35,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: balance < 0 ? colors.expense : null,
        ),
      ),
    );
  }

  /// A recognisable icon per account type, for a row with no icon key.
  IconData _iconFor(AccountType type) => switch (type) {
    AccountType.cash => Icons.payments_outlined,
    AccountType.bank => Icons.account_balance_outlined,
    AccountType.creditCard => Icons.credit_card,
    AccountType.digitalWallet => Icons.account_balance_wallet_outlined,
    AccountType.crypto => Icons.currency_bitcoin,
    AccountType.custom => Icons.wallet_outlined,
  };
}

/// The two empty states this list can reach. E-22.
///
/// E-22's rule is that "nothing yet" and "nothing matching the filter" are
/// different sentences, and its own table then lists Accounts as a surface
/// where the first cannot occur. Both halves are true, and they are about
/// different lists: the default one is never empty, while the archived filter
/// empties it the moment it is switched on with nothing archived.
class _NoAccounts extends StatelessWidget {
  const _NoAccounts({required this.showingArchived});

  final bool showingArchived;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      showingArchived
          // Not "nothing here" — the reason it is empty is the good news.
          ? 'Nothing archived. Every account you have is in the list above.'
          : 'No accounts yet.',
      textAlign: TextAlign.center,
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
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
              _ => 'Could not load your accounts.',
            },
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
