import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parse_receipt_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_profile.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/parsing/receipt_vocabulary.dart';

void main() {
  group('KeellsProfile', () {
    const profile = KeellsProfile();

    test('recognises the till receipt and the e-bill', () {
      expect(profile.recognises(['KEELLS SUPER', 'TEA 100.00']), isTrue);
      expect(profile.recognises(['Nexus No : 112105']), isTrue);
      expect(profile.recognises(['CARGILLS FOOD CITY']), isFalse);
    });

    test('adds its words to the standard ones, and only for its receipts', () {
      final keells = ReceiptVocabulary.standard.extendedBy(profile.vocabulary);

      expect(keells.discountWord.hasMatch('25.10% Dis'), isTrue);
      expect(keells.discountHeading.hasMatch('Nexus Deals 25%'), isTrue);
      expect(
        keells.roleOf('Change Money Redemption of Points'),
        LineRole.points,
      );
      expect(
        ReceiptVocabulary.standard.discountWord.hasMatch('25.10% Dis'),
        isFalse,
      );
    });

    test('is one of the parser\'s known profiles', () {
      expect(ParseReceiptText.knownProfiles, contains(isA<KeellsProfile>()));
    });
  });
}
