import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../domain/entities/receipt_image_source.dart';
import '../providers/receipt_scanner_providers.dart';

/// Scan Receipt: a photo from the camera or the gallery, read on device,
/// and handed to the review screen. FR-RCP-001, FR-RCP-002, FR-RCP-004;
/// the SDD's SCR-013.
///
/// Two buttons and a wait. The SDD's "camera viewfinder" is the
/// platform's own camera app, opened by `image_picker` — a viewfinder of
/// our own would be a second camera implementation to test on hardware
/// this project sees occasionally (E-28), for a photo the platform's
/// already takes better. Both routes end in the same path, and
/// [ScanReceiptController] runs the same pipeline on either.
///
/// A failure is printed here, under the buttons, rather than in a
/// snackbar: a refused permission needs a sentence that says which one
/// and what to do, and a receipt the recogniser could not read needs the
/// buttons still in reach for the next attempt. Backing out of the
/// picker shows nothing — it is not a failure.
class ScanReceiptPage extends ConsumerWidget {
  /// Creates the screen.
  const ScanReceiptPage({super.key});

  Future<void> _scan(
    BuildContext context,
    WidgetRef ref,
    ReceiptImageSource source,
  ) async {
    final scanned = await ref
        .read(scanReceiptControllerProvider.notifier)
        .scan(source);
    if (scanned == null || !context.mounted) return;
    await context.push(Routes.scanReceiptReview, extra: scanned);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final attempt = ref.watch(scanReceiptControllerProvider);
    final busy = attempt.isLoading;
    final error = attempt.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Receipt')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.document_scanner_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Photograph a receipt and every line on it becomes an '
                'expense, with a category suggested for each. You check '
                'the list before anything is saved.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Read on this phone. The photo never leaves it.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              if (busy) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Text(
                  'Reading the receipt…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
              ],
              if (error case final failure? when !busy)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    failure is Failure
                        ? failure.message
                        : 'Could not read the receipt.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => _scan(context, ref, ReceiptImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take a photo'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => _scan(context, ref, ReceiptImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from gallery'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
