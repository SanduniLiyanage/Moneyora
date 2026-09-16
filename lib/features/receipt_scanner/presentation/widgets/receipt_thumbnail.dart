import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/receipt_scanner_providers.dart';

/// The receipt photo at [path], when it is still on disk; a placeholder
/// when not, rather than an image error — the path is what matters and
/// it is kept either way. FR-RCP-012, FR-RCP-013.
///
/// Through [receiptImageProvider] rather than `Image.file`: a kept photo
/// is encrypted on disk (FR-RCP-012) and the picker's is not, and the
/// provider is what knows which is which. A photo that will not unlock
/// shows a lock, not the receipt placeholder — it is there, and it is not
/// the one that is gone.
///
/// Shared by the review screen and the history: the same photo, the same
/// answer when it is gone.
class ReceiptThumbnail extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final image = ref.watch(receiptImageProvider(path));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: switch (image) {
          AsyncData(value: final bytes?) => Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          AsyncData() => _Placeholder(Icons.receipt_long_outlined, theme),
          AsyncError() => _Placeholder(Icons.lock_outline, theme),
          _ => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
        },
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.icon, this.theme);

  final IconData icon;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
  );
}
