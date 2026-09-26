/// The platform's own save and open dialogs, for `.mora` files.
/// FR-BAK-001, FR-BAK-005.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../domain/entities/backup_file.dart';

/// Where a backup goes to and comes from: the user's choice, not the app's.
///
/// A seam the way the image picker's is, so the screens are tested against
/// a fake that answers as the platform would. The platform's dialogs reach
/// every place the user already keeps files — Downloads, a memory card,
/// Google Drive's document provider — which is what an offline-first app
/// can offer without an account of its own (E-38).
abstract class BackupFileGateway {
  /// Asks where to save [file] and saves it. False when the user backed
  /// out.
  Future<bool> save(BackupFile file);

  /// Asks for a backup to open and returns its bytes. Null when the user
  /// backed out.
  Future<Uint8List?> pick();
}

/// Fulfils [BackupFileGateway] with `file_picker`. Verified on the
/// emulator, not the VM: a method channel never answers there.
class FilePickerBackupFileGateway implements BackupFileGateway {
  /// Creates the gateway.
  const FilePickerBackupFileGateway();

  @override
  Future<bool> save(BackupFile file) async {
    final saved = await FilePicker.saveFile(
      fileName: file.name,
      bytes: file.bytes,
      dialogTitle: 'Save your backup',
    );
    return saved != null;
  }

  @override
  Future<Uint8List?> pick() async {
    // Any type, not `.mora` alone: Android's picker knows no MIME type for
    // it and would grey every backup out.
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choose a Moneyora backup',
    );
    return picked?.readAsBytes();
  }
}
