/// Every transaction as a printable PDF. FR-RPT-007.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/utils/currency_utils.dart';

/// One transaction as an export reads it: what the CSV and the PDF share.
class ExportRow {
  /// Creates a row.
  const ExportRow({
    required this.date,
    required this.type,
    required this.outgoing,
    required this.amountCents,
    required this.currency,
    required this.account,
    required this.category,
    required this.note,
  });

  /// `YYYY-MM-DD`, as stored.
  final String date;

  /// `Expense`, `Income`, `Transfer out` or `Transfer in`.
  final String type;

  /// Whether the money left the account — an expense or a transfer's out
  /// half — which is what signs the amount.
  final bool outgoing;

  /// Unsigned, in the account's minor units.
  final int amountCents;

  /// The account's ISO 4217 code.
  final String currency;

  /// The account's name.
  final String account;

  /// The category's name; empty for a transfer.
  final String category;

  /// The note; empty when there is none.
  final String note;

  /// [amountCents] with the sign of the money's direction.
  int get signedCents => outgoing ? -amountCents : amountCents;
}

/// [rows] as an A4 PDF: a table, oldest first, then the totals per currency.
///
/// Totals are per currency and never summed across them: an export has no
/// business converting at a rate the user may since have changed (E-34), and
/// a total mixing rupees and dollars is a number that means nothing.
///
/// The standard PDF fonts cover Latin-1 only, so a note in Sinhala or
/// Tamil is shown with `?` for what they cannot draw — embedding a font
/// that covers them would add megabytes to the app for a printout. The CSV
/// export carries every character; the screen says so.
Future<Uint8List> buildTransactionsPdf(
  List<ExportRow> rows, {
  required DateTime now,
}) {
  final doc = pw.Document(title: 'Moneyora transactions', creator: 'Moneyora');
  final day = now.toIso8601String().substring(0, 10);

  final totals = <String, ({int incoming, int outgoing})>{};
  for (final row in rows) {
    final t = totals[row.currency] ?? (incoming: 0, outgoing: 0);
    totals[row.currency] = row.outgoing
        ? (incoming: t.incoming, outgoing: t.outgoing + row.amountCents)
        : (incoming: t.incoming + row.amountCents, outgoing: t.outgoing);
  }

  String money(int cents, String code) =>
      _printable(formatCents(cents, currency: CurrencyFormat.forCode(code)));

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      // A ledger runs to thousands of rows; the package stops at 20 pages
      // unless told otherwise.
      maxPages: 1000,
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(
          'Moneyora transactions - $day',
          style: const pw.TextStyle(fontSize: 14),
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (context) => [
        if (rows.isEmpty)
          pw.Text('No transactions yet.')
        else
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Type', 'Category', 'Account', 'Note', 'Amount'],
            data: [
              for (final row in rows)
                [
                  row.date,
                  row.type,
                  _printable(row.category),
                  _printable(row.account),
                  _printable(row.note),
                  money(row.signedCents, row.currency),
                ],
            ],
            headerStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {5: pw.Alignment.centerRight},
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(width: 0.3),
            ),
          ),
        pw.SizedBox(height: 16),
        for (final MapEntry(key: code, value: t) in totals.entries)
          pw.Text(
            '$code: in ${money(t.incoming, code)}, '
            'out ${money(t.outgoing, code)}, '
            'net ${money(t.incoming - t.outgoing, code)}',
            style: const pw.TextStyle(fontSize: 9),
          ),
      ],
    ),
  );
  return doc.save();
}

/// [text] with what the standard fonts cannot draw replaced by `?`.
String _printable(String text) =>
    String.fromCharCodes(text.runes.map((c) => c <= 0xFF ? c : 0x3F));
