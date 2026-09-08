import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/widgets/account_icons.dart';

/// The account icon catalogue. FR-ACC-006, as amended by E-26.
///
/// The keys are the interesting part: they are written into `accounts.icon`
/// and read back for the life of the install, so a duplicate or a renamed key
/// silently changes what an existing account displays.
void main() {
  group('the catalogue', () {
    test('offers at least the twenty icons FR-ACC-006 asks for', () {
      expect(accountIcons.length, greaterThanOrEqualTo(20));
    });

    test('has no duplicate keys', () {
      // Two entries sharing a key means the picker can save one and display
      // the other, and `accountIconFor` would resolve to whichever came first.
      final keys = accountIcons.map((icon) => icon.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('has no duplicate glyphs', () {
      // Two identical-looking choices in a picker is a choice a user cannot
      // make. Not a correctness bug, but it looks like one.
      final glyphs = accountIcons.map((icon) => icon.icon).toList();
      expect(glyphs.toSet(), hasLength(glyphs.length));
    });

    test('every entry has a key and a label a person can read', () {
      for (final icon in accountIcons) {
        expect(icon.key.trim(), isNotEmpty, reason: 'a key is blank');
        expect(
          icon.label.trim(),
          isNotEmpty,
          reason: 'the icon "${icon.key}" has no label',
        );
      }
    });

    test('keys are lower case with no spaces, so a column can hold them', () {
      for (final icon in accountIcons) {
        expect(
          icon.key,
          matches(RegExp(r'^[a-z0-9]+$')),
          reason: '"${icon.key}" is not a safe storage key',
        );
      }
    });

    test('includes the default the seed writes', () {
      // default_seed.dart writes 'wallet' for the Cash account every install
      // starts with. If the catalogue ever loses that key, every fresh install
      // opens showing the fallback.
      expect(
        accountIcons.map((icon) => icon.key),
        contains(defaultAccountIconKey),
      );
    });
  });

  group('accountIconFor', () {
    test('resolves a known key to its glyph', () {
      expect(accountIconFor('bank'), Icons.account_balance);
      expect(accountIconFor('crypto'), Icons.currency_bitcoin);
    });

    test('falls back rather than throwing on an unknown key', () {
      // Not a programming error: a restored backup, a row from an older build,
      // or a future release that retires an icon all produce one. A crash is a
      // far worse answer than a wallet.
      expect(accountIconFor('a-key-from-2029'), accountIconFor('wallet'));
      expect(accountIconFor(''), accountIconFor('wallet'));
    });
  });
}
