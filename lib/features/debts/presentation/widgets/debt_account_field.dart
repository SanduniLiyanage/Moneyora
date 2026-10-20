import 'package:flutter/material.dart';

import '../../../../core/ports/account_reader.dart';
import '../../../../core/utils/currency_utils.dart';

/// The accounts a debt's money can move through: those in the currency
/// debts are shown in. FR-DBT-009, E-47.
///
/// A debt has no currency of its own: its amount is shown, and moves an
/// account, as rupees. Moving a dollar account by a rupee figure would
/// state something false, so only rupee accounts are offered.
List<AccountOption> debtAccounts(List<AccountOption> accounts) => [
  for (final account in accounts)
    if (account.currency.toUpperCase() == CurrencyFormat.lkr.code) account,
];

/// An optional account, chosen from [accounts], with "No account" first.
/// FR-DBT-009.
///
/// One the list no longer offers — archived since, or in another currency
/// — stays chosen and says so, rather than leaving the field with a value
/// it has no item for.
class DebtAccountField extends StatelessWidget {
  /// Creates the field.
  const DebtAccountField({
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.helper,
    super.key,
  });

  /// What the account is to the debt: "Lent from", "Paid back into".
  final String label;

  /// The accounts that can be chosen.
  final List<AccountOption> accounts;

  /// The account chosen, or null for none.
  final int? value;

  /// Called with the account chosen, or null for none.
  final ValueChanged<int?> onChanged;

  /// A line under the field, when there is something to say.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final listed = value == null || accounts.any((a) => a.id == value);
    return DropdownButtonFormField<int?>(
      // Remade when the choice changes from outside, which the field's own
      // value would otherwise outlive.
      key: ValueKey((label, value)),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        // "No account" is a choice, shown in the field; a resting label
        // would sit on top of it.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: helper,
        helperMaxLines: 4,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<int?>(child: Text('No account')),
        for (final account in accounts)
          DropdownMenuItem<int?>(
            value: account.id,
            child: Text(account.name, overflow: TextOverflow.ellipsis),
          ),
        if (!listed)
          DropdownMenuItem<int?>(
            value: value,
            child: const Text(
              'An account no longer listed',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
