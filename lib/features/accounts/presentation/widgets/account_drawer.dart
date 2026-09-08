import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/account_icons.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/account_totals.dart';
import '../providers/account_providers.dart';

/// The side panel of accounts and their balances. FR-ACC-003.
///
/// Attached by `core/router/app_router.dart` rather than imported by the home
/// screen, because a feature importing another feature is what rule 4 of
/// `scripts/check_architecture.sh` forbids. The router is already the place
/// that names every feature's pages, the same way `injection.dart` is the one
/// place allowed to name concrete `data/` classes.
///
/// Archived accounts are absent (FR-ACC-004) — that is what archiving is for.
class AccountDrawer extends ConsumerWidget {
  /// Creates the drawer.
  const AccountDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider(false));

    return Drawer(
      child: SafeArea(
        child: switch (accounts) {
          AsyncData(:final value) => _Accounts(accounts: value),
          AsyncError(:final error) => _Problem(error: error),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _Accounts extends StatelessWidget {
  const _Accounts({required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = AccountTotals.from(accounts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Total(totals: totals),
        const Divider(height: 1),
        Expanded(
          // E-22 lists the accounts surface as one whose empty state "cannot
          // occur": the seed creates a Cash account and ArchiveAccount refuses
          // to archive the last one. Handled anyway, because "cannot occur" is
          // a claim about today's code and an empty ListView would otherwise
          // present as a drawer that failed to load.
          child: accounts.isEmpty
              ? const _NoAccounts()
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: accounts.length,
                  itemBuilder: (context, index) =>
                      _AccountTile(account: accounts[index]),
                ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Add account'),
          onTap: () {
            // Close the panel first. Pushing over an open drawer leaves it
            // open underneath, so returning from the form lands on a screen
            // with the panel still covering it.
            Navigator.of(context).pop();
            context.push(Routes.accountForm);
          },
        ),
        if (totals.hasExcludedForeign) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text(
              // E-25. Saying what was left out, and why, rather than
              // converting at an invented rate or adding dollars to rupees.
              // The number above is then correct rather than approximate.
              totals.excludedForeignCount == 1
                  ? 'One account in another currency is not counted — Moneyora '
                        'cannot convert between currencies yet.'
                  : '${totals.excludedForeignCount} accounts in other '
                        'currencies are not counted — Moneyora cannot convert '
                        'between currencies yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.totals});

  final AccountTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total balance',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatCents(
              totals.totalCents,
              currency: CurrencyFormat.forCode(totals.baseCurrency),
            ),
            style: theme.textTheme.headlineSmall?.copyWith(
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
  const _AccountTile({required this.account});

  final Account account;

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
      onTap: () {
        Navigator.of(context).pop();
        context.push(Routes.accountForm, extra: account);
      },
      // Only worth saying when it is not the assumed one; repeating "LKR" on
      // every row on an install that has never seen another currency is noise.
      subtitle:
          account.currency.toUpperCase() == AccountTotals.defaultBaseCurrency
          ? null
          : Text(account.currency.toUpperCase()),
      trailing: Text(
        formatCents(
          balance,
          currency: CurrencyFormat.forCode(account.currency),
        ),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: balance < 0 ? colors.expense : null,
        ),
      ),
    );
  }

  /// A recognisable icon per account type.
  ///
  /// Not FR-ACC-006's twenty-plus icon catalogue — that is the account form's
  /// business, and arrives with it. This maps the six types the entity already
  /// has so the drawer is scannable rather than six identical rows.
  IconData _iconFor(AccountType type) => switch (type) {
    AccountType.cash => Icons.payments_outlined,
    AccountType.bank => Icons.account_balance_outlined,
    AccountType.creditCard => Icons.credit_card,
    AccountType.digitalWallet => Icons.account_balance_wallet_outlined,
    AccountType.crypto => Icons.currency_bitcoin,
    AccountType.custom => Icons.wallet_outlined,
  };
}

class _NoAccounts extends StatelessWidget {
  const _NoAccounts();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Text('No accounts yet.', textAlign: TextAlign.center),
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
