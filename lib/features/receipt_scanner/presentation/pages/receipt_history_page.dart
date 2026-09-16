import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/receipt_scan.dart';
import '../providers/receipt_scanner_providers.dart';
import '../widgets/receipt_thumbnail.dart';

/// Receipt history: every receipt scanned so far, newest first, with its
/// photo, date and total, narrowed by a search. FR-RCP-013; the SDD's
/// SCR-015.
///
/// The search runs through `GetScanHistory`, so what matches is the use
/// case's rule and not this screen's — typed text goes to the provider
/// as it is, and the last list stays on screen while the next one loads,
/// so a keystroke never blanks the page.
///
/// Tapping a row opens the photo: FR-RCP-012 keeps it "for future
/// reference", and this is the reference. Re-scanning from here is
/// FR-RCP-014's, not built yet.
class ReceiptHistoryPage extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ReceiptHistoryPage({super.key});

  @override
  ConsumerState<ReceiptHistoryPage> createState() => _ReceiptHistoryPageState();
}

class _ReceiptHistoryPageState extends ConsumerState<ReceiptHistoryPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  List<ReceiptScan>? _shown;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(receiptHistoryProvider(_query));
    if (history case AsyncData(value: final scans)) _shown = scans;
    final shown = _shown;

    final Widget body;
    if (history case AsyncError(:final error)) {
      body = _Message(
        error is Failure ? error.message : 'Could not read the receipts.',
      );
    } else if (shown != null && shown.isNotEmpty) {
      // Also while a new search loads: the last list stays up rather
      // than a spinner flashing between keystrokes.
      body = _ReceiptList(scans: shown);
    } else if (history.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_query.trim().isNotEmpty) {
      body = _Message('Nothing matches "${_query.trim()}".');
    } else {
      body = const _NoReceipts();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt history')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (text) => setState(() => _query = text),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by store, item or receipt number',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _ReceiptList extends StatelessWidget {
  const _ReceiptList({required this.scans});

  final List<ReceiptScan> scans;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [for (final scan in scans) _ReceiptRow(scan: scan)],
  );
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.scan});

  final ReceiptScan scan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final merchant = scan.merchantName?.trim();
    final count = scan.items.length;
    final status = statusLabel(scan.status);
    final total = scan.totalCents;
    return Card(
      child: ListTile(
        leading: ReceiptThumbnail(path: scan.imagePath, width: 48, height: 64),
        title: Text(
          merchant == null || merchant.isEmpty ? 'Unknown store' : merchant,
        ),
        subtitle: Text(
          '${dateLabel(scan)} · $count item${count == 1 ? '' : 's'}'
          '${status == null ? '' : ' · $status'}',
        ),
        trailing: Text(
          total == null ? '—' : formatCents(total),
          style: theme.textTheme.titleMedium,
        ),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => _ReceiptPhotoPage(scan: scan)),
        ),
      ),
    );
  }

  /// The date printed on the receipt when one was read; otherwise when it
  /// was scanned, said so, because the two can be weeks apart.
  static String dateLabel(ReceiptScan scan) {
    final format = DateFormat.yMMMd();
    if (scan.receiptDate case final printed?) return format.format(printed);
    if (scan.scannedAt case final scanned?) {
      return 'Scanned ${format.format(scanned)}';
    }
    return 'Date unknown';
  }

  /// A word for a scan that is not in the ledger; nothing for one that is,
  /// which is every scan the confirm step writes.
  static String? statusLabel(ReceiptScanStatus status) => switch (status) {
    ReceiptScanStatus.confirmed => null,
    ReceiptScanStatus.pending => 'not confirmed',
    ReceiptScanStatus.rejected => 'discarded',
  };
}

/// The photo, full size, pinch-to-zoom. FR-RCP-012's "future reference".
class _ReceiptPhotoPage extends StatelessWidget {
  const _ReceiptPhotoPage({required this.scan});

  final ReceiptScan scan;

  @override
  Widget build(BuildContext context) {
    final file = File(scan.imagePath);
    final merchant = scan.merchantName?.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          merchant == null || merchant.isEmpty ? 'Receipt' : merchant,
        ),
      ),
      body: file.existsSync()
          ? InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.file(file, fit: BoxFit.contain)),
            )
          : const _Message('The photo is no longer on this phone.'),
    );
  }
}

/// E-22: say what belongs here and the one action that fills it.
class _NoReceipts extends StatelessWidget {
  const _NoReceipts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No receipts yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Every receipt you scan and confirm is kept here with its '
              'photo, so you can find it again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go(Routes.scanReceipt),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan a receipt'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
