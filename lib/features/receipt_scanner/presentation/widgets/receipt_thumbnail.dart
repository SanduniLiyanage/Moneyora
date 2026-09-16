import 'dart:io';

import 'package:flutter/material.dart';

/// The receipt photo at [path], when it is still on disk; a placeholder
/// when not, rather than an image error — the path is what matters and
/// it is kept either way. FR-RCP-012, FR-RCP-013.
///
/// Shared by the review screen and the history: the same photo, the same
/// answer when it is gone.
class ReceiptThumbnail extends StatelessWidget {
  /// Creates the thumbnail.
  const ReceiptThumbnail({
    required this.path,
    this.width = 72,
    this.height = 96,
    super.key,
  });

  /// Where the photo lives on disk.
  final String path;

  /// The box the photo is cropped to fill.
  final double width;

  /// The box the photo is cropped to fill.
  final double height;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}
