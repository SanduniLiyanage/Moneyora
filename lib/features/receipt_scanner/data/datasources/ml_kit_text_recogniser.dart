import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

import 'ocr_local_datasource.dart';

/// The [TextRecogniser] that ships: ML Kit's Latin-script recogniser, on
/// device, no network (FR-RCP-004; the iOS floor it sets is E-20).
///
/// Latin only, deliberately. The other four scripts each add a model to the
/// APK, `proguard-rules.pro` already has to `-dontwarn` them away for the
/// release build, and nothing in the SRS asks for a receipt in Sinhala or
/// Tamil script — the keyword dictionary is English.
///
/// Not unit-tested: everything it does is a platform-channel call. Proving
/// it needs the emulator or the phone and a real receipt photo.
class MlKitTextRecogniser implements TextRecogniser {
  /// Creates the recogniser. Cheap until the first [processImage], which
  /// loads the model.
  MlKitTextRecogniser()
    : _recognizer = mlkit.TextRecognizer(
        script: mlkit.TextRecognitionScript.latin,
      );

  final mlkit.TextRecognizer _recognizer;

  @override
  Future<mlkit.RecognizedText> processImage(mlkit.InputImage image) =>
      _recognizer.processImage(image);

  @override
  Future<void> close() => _recognizer.close();
}
