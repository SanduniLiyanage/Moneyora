import 'receipt_vocabulary.dart';

/// One shop's way of printing a receipt, laid over the generic rules.
/// FR-RCP-005, E-45.
///
/// The parser is written for receipts in general; a profile exists for
/// what one chain prints that no rule should assume of every receipt — a
/// word only its till abbreviates that way, a heading only it prints. A
/// profile that recognises a receipt adds its [vocabulary] to the
/// standard one for that receipt alone, so a profile can only ever make
/// its own shop's receipts read better.
///
/// To add a shop: subclass, say what on the receipt names it, give the
/// words it prints differently, add it to `ParseReceiptText.knownProfiles`,
/// and add one of its receipts — as ML Kit read it — to the parser's
/// fixtures.
abstract class ReceiptProfile {
  /// Const so the profile list can be.
  const ReceiptProfile();

  /// The shop, for tests and logs.
  String get name;

  /// True when [lines] are this shop's receipt.
  bool recognises(List<String> lines);

  /// The words this shop's receipts print that the standard vocabulary
  /// does not know.
  ReceiptVocabulary get vocabulary;
}

/// Keells supermarkets: the till receipt and the e-bill. FR-RCP-005.
///
/// The e-bill (the first real one, 2026-10-09) lists its discounts as a
/// block under `Discounts` and a promotion heading — `Nexus Deals 25%` —
/// each line naming its item by row and article code and abbreviating
/// discount to `Dis`: `2 100334 25.20% Dis Rs: 92.00`. Below the totals,
/// `Change Money Redemption of Points` is points spent, not change.
class KeellsProfile extends ReceiptProfile {
  /// The profile.
  const KeellsProfile();

  static final _keells = RegExp(r'\bkeells\b|\bnexus\b', caseSensitive: false);

  @override
  String get name => 'Keells';

  @override
  bool recognises(List<String> lines) => lines.any(_keells.hasMatch);

  @override
  ReceiptVocabulary get vocabulary => ReceiptVocabulary(
    discountWords: const ['dis'],
    discountHeadings: const [r'deals?'],
    pointsLabels: const [r'change\s+money'],
  );
}
