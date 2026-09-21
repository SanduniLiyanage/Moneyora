import '../../../../core/errors/failures.dart';

/// What a passcode may look like: four to six digits. FR-SET-005.
///
/// One place for the rule, read by every use case that takes a PIN and by the
/// screens that collect one, so the sentence a screen shows is the sentence
/// the use case would refuse with.
abstract final class PasscodeFormat {
  /// The fewest digits a PIN may have.
  static const int minLength = 4;

  /// The most digits a PIN may have.
  static const int maxLength = 6;

  static final RegExp _digits = RegExp(r'^\d+$');

  /// The refusal for [pin], or null when it is acceptable.
  static ValidationFailure? validate(String pin) {
    if (pin.length < minLength ||
        pin.length > maxLength ||
        !_digits.hasMatch(pin)) {
      return const ValidationFailure(
        'Enter a PIN of 4 to 6 digits.',
        field: 'pin',
      );
    }
    return null;
  }
}
