/// The analytics account filter. FR-RPT-003.
///
/// "All Accounts, or any specific single account" — a dropdown rather than a
/// second chip row, because the period chips are a closed set of six that a
/// user reads at a glance while accounts are user data of unknown length, and
/// because `transfer_page.dart` already renders an account list this way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ports/account_reader.dart';
import '../providers/analytics_providers.dart';

/// The label for "no account filter". FR-RPT-003's first option.
const String allAccountsLabel = 'All accounts';

/// A dropdown over every account, writing to [analyticsAccountFilterProvider].
class AccountFilter extends ConsumerWidget {
  /// Creates the filter.
  const AccountFilter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountOptionsProvider);
    final selected = ref.watch(analyticsAccountFilterProvider);
    final options = accounts.valueOrNull ?? const <AccountOption>[];

    // An account that has been deleted or archived out from under the filter
    // would leave the dropdown with a value that is not in its own items,
    // which is an assertion failure rather than a visible bug. Falling back to
    // "All accounts" is also the honest reading: the filtered account is gone.
    final value = options.any((a) => a.id == selected) ? selected : null;
    if (value != selected) {
      // Off the build: the provider cannot be written to while it is being
      // read, and the chart below is watching the same value.
      Future.microtask(
        () => ref.read(analyticsAccountFilterProvider.notifier).state = null,
      );
    }

    return Row(
      children: [
        Icon(
          Icons.account_balance_wallet_outlined,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: value,
              isExpanded: true,
              isDense: true,
              style: theme.textTheme.bodyMedium,
              items: [
                const DropdownMenuItem<int?>(child: Text(allAccountsLabel)),
                for (final account in options)
                  DropdownMenuItem<int?>(
                    value: account.id,
                    child: Text(account.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) =>
                  ref.read(analyticsAccountFilterProvider.notifier).state = id,
            ),
          ),
        ),
      ],
    );
  }
}
