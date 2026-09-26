import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// A sealed backup, ready to be saved wherever the user chooses.
/// FR-BAK-001, E-08.
///
/// Bytes rather than a path: the platform's save dialog takes bytes, and a
/// file the app wrote first would be one more copy of the ledger on disk.
class BackupFile extends Equatable {
  /// Creates a backup file.
  const BackupFile({required this.name, required this.bytes});

  /// The name to suggest: `moneyora-2026-09-27.mora`.
  final String name;

  /// The sealed contents.
  final Uint8List bytes;

  @override
  List<Object?> get props => [name, bytes];
}
