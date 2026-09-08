/// The built-in icons an account can be given. FR-ACC-006.
///
/// In `core/widgets/` rather than the accounts feature because the entry
/// screen's account selector needs the same icons, and that screen lives in
/// `features/transactions/` — rule 4 of `check_architecture.sh` forbids one
/// feature importing another, and this is a lookup table with no business
/// logic, which is exactly what `ARCHITECTURE.md` §5 sends here.
///
/// ## Why these are not the brands the SRS names
///
/// FR-ACC-006 asks for "Cash, AMEX, VISA, Mastercard, PayPal, Bitcoin, JCB,
/// QIWI, Stripe, Discover, and others". Eight of those are registered
/// trademarks whose marks cannot simply be drawn and shipped, and Material
/// Icons — which ship with Flutter under Apache-2.0 — contain none of them.
///
/// So the catalogue below covers the same ground by *what an account is for*
/// rather than by card brand, and is recorded as a deviation in
/// [E-26](../../../docs/SPEC_ERRATA.md) rather than applied silently. The
/// requirement's countable promise — twenty or more built-in icons — is met.
library;

import 'package:flutter/material.dart';

/// One pickable account icon.
class AccountIcon {
  /// Creates an entry in the catalogue.
  const AccountIcon({
    required this.key,
    required this.label,
    required this.icon,
  });

  /// What is written to `accounts.icon`.
  ///
  /// A stable string, never the enum name or the list position: an icon
  /// reordered or renamed in a later release must not silently change what
  /// every existing account displays.
  final String key;

  /// What the picker announces, and what a screen reader reads.
  final String label;

  /// The glyph itself.
  final IconData icon;
}

/// The catalogue. FR-ACC-006 requires twenty or more; this has twenty-five.
///
/// Ordered roughly by how likely a first-time user is to want one, because a
/// grid is scanned from the top left and the common cases should be there.
const List<AccountIcon> accountIcons = [
  AccountIcon(
    key: 'wallet',
    label: 'Wallet',
    icon: Icons.account_balance_wallet,
  ),
  AccountIcon(key: 'cash', label: 'Cash', icon: Icons.payments),
  AccountIcon(key: 'bank', label: 'Bank', icon: Icons.account_balance),
  AccountIcon(key: 'card', label: 'Payment card', icon: Icons.credit_card),
  AccountIcon(key: 'savings', label: 'Savings', icon: Icons.savings),
  AccountIcon(key: 'mobile', label: 'Mobile wallet', icon: Icons.smartphone),
  AccountIcon(
    key: 'crypto',
    label: 'Cryptocurrency',
    icon: Icons.currency_bitcoin,
  ),
  AccountIcon(
    key: 'exchange',
    label: 'Foreign currency',
    icon: Icons.currency_exchange,
  ),
  AccountIcon(key: 'investment', label: 'Investment', icon: Icons.trending_up),
  AccountIcon(key: 'business', label: 'Business', icon: Icons.business_center),
  AccountIcon(key: 'salary', label: 'Salary', icon: Icons.work),
  AccountIcon(
    key: 'joint',
    label: 'Joint or household',
    icon: Icons.family_restroom,
  ),
  AccountIcon(key: 'emergency', label: 'Emergency fund', icon: Icons.shield),
  AccountIcon(key: 'locked', label: 'Fixed deposit', icon: Icons.lock),
  AccountIcon(key: 'goal', label: 'Goal', icon: Icons.flag),
  AccountIcon(key: 'giftcard', label: 'Gift card', icon: Icons.card_giftcard),
  AccountIcon(key: 'loyalty', label: 'Loyalty points', icon: Icons.star),
  AccountIcon(key: 'travel', label: 'Travel', icon: Icons.flight),
  AccountIcon(key: 'home', label: 'Home', icon: Icons.home),
  AccountIcon(key: 'car', label: 'Vehicle', icon: Icons.directions_car),
  AccountIcon(key: 'education', label: 'Education', icon: Icons.school),
  AccountIcon(key: 'health', label: 'Health', icon: Icons.local_hospital),
  AccountIcon(key: 'shopping', label: 'Shopping', icon: Icons.shopping_bag),
  AccountIcon(key: 'pettycash', label: 'Petty cash', icon: Icons.receipt_long),
  AccountIcon(key: 'other', label: 'Other', icon: Icons.more_horiz),
];

/// The default for an account that has never chosen one.
///
/// `wallet` because that is what `default_seed.dart` writes for the Cash
/// account every install starts with.
const String defaultAccountIconKey = 'wallet';

/// The glyph for [key], or the default when nothing matches.
///
/// Never throws. An unknown key is not a programming error: a restored backup,
/// a row written by an older build, or a future release that retires an icon
/// can all produce one, and a crash is a much worse answer than a wallet.
IconData accountIconFor(String key) {
  for (final entry in accountIcons) {
    if (entry.key == key) return entry.icon;
  }
  for (final entry in accountIcons) {
    if (entry.key == defaultAccountIconKey) return entry.icon;
  }
  return Icons.account_balance_wallet;
}
