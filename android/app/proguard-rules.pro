# Moneyora — R8 / ProGuard keep rules
#
# Until this file existed, `flutter build apk --release` failed outright and
# nothing noticed, because CI built a debug APK and debug does not run R8. The
# minifier had never executed on this project across 38 pull requests. See
# E-09 in docs/SPEC_ERRATA.md.
#
# Rules here need a comment saying why. A keep rule with no reason is
# indistinguishable from a keep rule that is no longer needed, and the cost of
# guessing wrong is either a runtime crash or dead weight in the APK.

# ---------------------------------------------------------------------------
# ML Kit text recognition — the non-Latin scripts (E-09)
# ---------------------------------------------------------------------------
#
# `google_mlkit_text_recognition` exposes five scripts, and its single
# `TextRecognizer.initialize` method references the options class for every one
# of them so it can switch on whichever the caller asks for:
#
#   Missing class com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
#   Missing class ...devanagari.DevanagariTextRecognizerOptions
#   Missing class ...japanese.JapaneseTextRecognizerOptions
#   Missing class ...korean.KoreanTextRecognizerOptions
#   ...and the $Builder of each.
#
# Each script ships as a *separate* Maven artefact carrying its own recognition
# model. The plugin declares none of them, so R8 sees eight unresolvable
# references and stops the build.
#
# There are two ways to satisfy R8, and the other one is a trap. Adding the four
# missing dependencies also makes the error go away — and ships four text
# recognition models this app never calls, into an artefact with an 80 MB budget
# (SRS 2.4). The receipt scanner reads Sri Lankan receipts in Latin script; the
# Latin recogniser is bundled with the base artefact and is the only one used.
#
# So: tell R8 these references are known to be absent. The `initialize` method
# survives, and asking it for Japanese would throw at runtime — which is the
# honest outcome for a model the app deliberately does not carry, and is
# unreachable because nothing requests a script.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
