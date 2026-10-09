import 'package:equatable/equatable.dart';

import 'priced_line.dart';
import 'receipt_dates.dart';
import 'receipt_vocabulary.dart';

/// The fields above a receipt's items, and which lines they used.
class ReceiptHeader extends Equatable {
  /// Creates a header.
  const ReceiptHeader({
    this.merchantName,
    this.merchantGuessed = false,
    this.receiptDate,
    this.dateGuessed = false,
    this.receiptNumber,
    this.consumed = const {},
  });

  /// The store's name, or null when nothing on the receipt reads as one.
  final String? merchantName;

  /// True when [merchantName] is the sender of the email the receipt came
  /// in, not a line of the receipt.
  final bool merchantGuessed;

  /// When it was bought; midnight when only a date was read.
  final DateTime? receiptDate;

  /// True when [receiptDate] is when a message carrying the receipt was
  /// sent, not a date the receipt printed.
  final bool dateGuessed;

  /// The receipt's own printed identifier (E-31).
  final String? receiptNumber;

  /// Indexes of the lines that are not the receipt's body: the phone's and
  /// the email's text around it, and the lines read for these fields.
  final Set<int> consumed;

  @override
  List<Object?> get props => [
    merchantName,
    merchantGuessed,
    receiptDate,
    dateGuessed,
    receiptNumber,
    consumed,
  ];
}

/// The merchant, the date and time, and the receipt number, from a
/// receipt's lines. FR-RCP-005, FR-RCP-011, E-45.
///
/// The first stage of `ParseReceiptText`. Decisions the SRS does not make:
/// - **The phone and the email are not the receipt.** A screenshot carries
///   the status bar (`19:14 ! 4G 39`); a forwarded e-bill carries
///   `Forwarded message`, `From:`, `To:`, `Subject:` and the email's own
///   `Date:`. None of it is read for any field, and none of it is an item.
///   A status bar is a clock among the first two lines with no word beside
///   it; an email header is a block opened by `Forwarded message` or a
///   `From:` with an address, and closed by its `Subject:`.
/// - **A labelled store is the merchant.** `Billed Store : Keells -
///   Katubedda` beats the first line of the receipt, which on an e-bill is
///   a logo's alt text or nothing. Failing a label, the first line above
///   the items that reads as a name — three letters in a row, not an
///   address, a phone number or a title — is the merchant, as before.
///   Failing that, the email's sender, marked as guessed; failing that,
///   nothing, for the user to fill in rather than a line of noise.
/// - **The receipt's date beats the email's.** A labelled `Bill Date`
///   first, then the first date printed; the email header's date only when
///   the receipt printed none, turned from its zone to local time and
///   marked as guessed. `Date: Mon, 05 Oct 2026 11:26:04 +0000` is when
///   the e-bill was sent, in UTC — five and a half hours from what the
///   till printed.
/// - **A labelled time gives a bare date its time** — `Billed Time
///   :16:54:43`, `TIME : 05:12:13 PM`, `Time End: 14:31:32` — wherever on
///   the receipt it is, and OCR's `ime End` is still the label.
/// - **A loyalty block below the bill is not the bill.** From the first
///   line naming points or loyalty after the bill's total or payment —
///   `Loyalty Customer`, `Star Points` — to the end, nothing is read for
///   the items or the total: its `Total:` is a points balance. Its date is
///   the bill's date only when the bill's own was lost (a photo that cut
///   the day off), and then the bill's own labelled time beats the block's.
class ReceiptHeaderReader {
  /// Creates a reader. [localOffset] is the device's offset from UTC, for
  /// an email date; the clock's own when null.
  const ReceiptHeaderReader(this._vocabulary, {this.localOffset});

  final ReceiptVocabulary _vocabulary;

  /// The device's offset from UTC; the clock's own when null.
  final Duration? localOffset;

  /// Reads the header off [lines].
  ReceiptHeader read(List<String> lines) {
    final collapsed = [for (final l in lines) PricedLine.collapse(l)];
    final chrome = _Chrome.of(collapsed, localOffset: localOffset);
    final consumed = {...chrome.lines};
    bool open(int i) => collapsed[i].isNotEmpty && !consumed.contains(i);
    final loyalty = _loyaltyBlock(collapsed, open);
    consumed.addAll(loyalty);
    // A date shares its line with a receipt number as often as not.
    bool printed(int i) =>
        collapsed[i].isNotEmpty &&
        !chrome.lines.contains(i) &&
        !loyalty.contains(i);

    String? number;
    for (var i = 0; i < collapsed.length && number == null; i++) {
      if (!open(i)) continue;
      number = _receiptNumber.firstMatch(collapsed[i])?[1];
      if (number != null) consumed.add(i);
    }

    // The labelled date first, then the first printed; each line used is
    // never an item.
    (DateTime, int)? labelled;
    (DateTime, int)? first;
    for (var i = 0; i < collapsed.length && labelled == null; i++) {
      if (!printed(i)) continue;
      final date = ReceiptDates.dateOf(collapsed[i]);
      if (date == null) continue;
      if (_vocabulary.billDateLabel.hasMatch(collapsed[i])) {
        labelled = (date, i);
      } else {
        first ??= (date, i);
      }
    }
    var date = (labelled ?? first)?.$1;
    if ((labelled ?? first)?.$2 case final line?) consumed.add(line);
    final fromLoyalty = date == null;
    if (fromLoyalty) {
      date = [for (final i in loyalty) ReceiptDates.dateOf(collapsed[i])]
          .nonNulls
          .firstOrNull;
    }
    if (date != null && (fromLoyalty || (date.hour == 0 && date.minute == 0))) {
      for (var i = 0; i < collapsed.length; i++) {
        if (!open(i)) continue;
        if (!_vocabulary.timeLabel.hasMatch(_vocabulary.mend(collapsed[i]))) {
          continue;
        }
        if (ReceiptDates.dateOf(collapsed[i]) != null) continue;
        final time = ReceiptDates.timeOf(collapsed[i]);
        if (time == null) continue;
        date = ReceiptDates.at(date!, time);
        consumed.add(i);
        break;
      }
    }

    var merchant = _labelledMerchant(collapsed, open, consumed);
    if (merchant == null) {
      final start = _bodyStart(collapsed, open);
      for (var i = 0; i < start; i++) {
        if (!open(i) || !_couldBeMerchant(collapsed[i])) continue;
        merchant = collapsed[i];
        consumed.add(i);
        break;
      }
    }
    final merchantGuessed = merchant == null && chrome.sender != null;
    final dateGuessed = date == null && chrome.sentAt != null;

    return ReceiptHeader(
      merchantName: merchant ?? chrome.sender,
      merchantGuessed: merchantGuessed,
      receiptDate: date ?? chrome.sentAt,
      dateGuessed: dateGuessed,
      receiptNumber: number,
      consumed: consumed,
    );
  }

  /// `Billed Store : Keells- Katubedda` → `Keells - Katubedda`.
  String? _labelledMerchant(
    List<String> lines,
    bool Function(int) open,
    Set<int> consumed,
  ) {
    for (var i = 0; i < lines.length; i++) {
      if (!open(i)) continue;
      final m = _vocabulary.merchantLabel.firstMatch(lines[i]);
      if (m == null) continue;
      final name = tidyName(m[1]!);
      if (!_hasName.hasMatch(name)) continue;
      consumed.add(i);
      return name;
    }
    return null;
  }

  /// The indexes of a loyalty block: from the first unpriced line naming
  /// points or loyalty after the bill's first total or payment line, to the
  /// end. Empty when there is none.
  Set<int> _loyaltyBlock(List<String> lines, bool Function(int) open) {
    int? paid;
    for (var i = _bodyStart(lines, open); i < lines.length; i++) {
      if (!open(i)) continue;
      final priced = PricedLine.of(lines[i]);
      if (priced == null) continue;
      if (_paidRoles.contains(_vocabulary.roleOf(priced.rest))) {
        paid = i;
        break;
      }
    }
    if (paid == null) return const {};
    for (var i = paid + 1; i < lines.length; i++) {
      if (!open(i) || PricedLine.of(lines[i]) != null) continue;
      if (_vocabulary.loyaltyMarker.hasMatch(_vocabulary.mend(lines[i]))) {
        return {for (var j = i; j < lines.length; j++) j};
      }
    }
    return const {};
  }

  static const _paidRoles = {LineRole.net, LineRole.total, LineRole.tender};

  /// The index of the first line that starts the items — a price with
  /// cents, or a quantity multiplied out, that is not a total, a payment
  /// or a discount — or the line count when none does.
  int _bodyStart(List<String> lines, bool Function(int) open) {
    for (var i = 0; i < lines.length; i++) {
      if (!open(i)) continue;
      final priced = PricedLine.of(lines[i]);
      if (priced == null || priced.cents <= 0 || !priced.startsBody) continue;
      if (_vocabulary.roleOf(priced.rest) != null) continue;
      if (_vocabulary.discountWord.hasMatch(priced.rest)) continue;
      if (ReceiptVocabulary.noise.hasMatch(lines[i])) continue;
      return i;
    }
    return lines.length;
  }

  bool _couldBeMerchant(String line) =>
      PricedLine.of(line) == null &&
      _hasName.hasMatch(line) &&
      !ReceiptVocabulary.noise.hasMatch(line) &&
      !ReceiptVocabulary.headerNoise.hasMatch(line) &&
      !ReceiptVocabulary.isColumnTitles(line) &&
      !_vocabulary.discountHeading.hasMatch(line);

  /// Three letters in a row: a name, not `19:14 !!4G39` or `<`.
  static final _hasName = RegExp('[A-Za-z]{3}');

  /// [name] with a dash spaced as a separator when OCR closed one side of
  /// it up — `Keells- Katubedda` — and its trailing punctuation dropped. A
  /// dash with no space either side (`7-ELEVEN`) is part of the name.
  static String tidyName(String name) => name
      .replaceAll(RegExp(r'(?<=\S)\s*-\s+(?=\S)|(?<=\S)\s+-\s*(?=\S)'), ' - ')
      .replaceAll(RegExp(r'[\s:;,.|-]+$'), '')
      .trim();

  /// `Receipt No: 4521`, `INV# A-0042`, `Bill 000123`. The token must hold
  /// a digit, so `INVOICE TOTAL` captures nothing, and must not be a price,
  /// so `transaction: 535.00` is not receipt 535. `Bil|` is how ML Kit read
  /// `Bill` on the first real receipt.
  static final _receiptNumber = RegExp(
    r'\b(?:receipt|invoice|inv|bil[l|1i]?|rcpt|txn|trans(?:action)?)\s*'
    r'(?:no|number|num|id|#)?\.?\s*[:#-]?\s*'
    r'((?=[A-Z0-9/-]*\d)[A-Z0-9][A-Z0-9/-]*)(?![A-Z0-9/-]|[.,]\d)',
    caseSensitive: false,
  );
}

/// The lines around a receipt that the phone or the email put there.
class _Chrome {
  const _Chrome(this.lines, {this.sentAt, this.sender});

  factory _Chrome.of(List<String> lines, {Duration? localOffset}) {
    final chrome = <int>{};
    DateTime? sentAt;
    String? sender;
    var inEmail = false;
    var seen = 0;

    for (final (i, line) in lines.indexed) {
      if (line.isEmpty) continue;
      seen++;

      if (seen <= 2 &&
          _clock.hasMatch(line) &&
          !_word.hasMatch(line) &&
          ReceiptDates.dateOf(line) == null) {
        chrome.add(i);
        continue;
      }
      if (!_letterOrDigit.hasMatch(line)) {
        // `<`, `|`, a rule of dashes: an icon or a divider.
        chrome.add(i);
        continue;
      }
      if (_forwarded.hasMatch(line)) {
        chrome.add(i);
        inEmail = true;
        continue;
      }
      final field = _emailField.firstMatch(line)?[1]?.toLowerCase();
      final isSentDate = field == 'date' && _sentDate.hasMatch(line);
      if (field != null &&
          (inEmail ||
              isSentDate ||
              _address.hasMatch(line) ||
              _alwaysEmail.contains(field))) {
        chrome.add(i);
        if (field == 'date') {
          sentAt ??= ReceiptDates.zonedDateOf(line, localOffset: localOffset);
        }
        if (field == 'from') {
          sender ??= _senderName(line);
          inEmail = true;
        }
        if (field == 'subject') inEmail = false;
        continue;
      }
      inEmail = false;
    }
    return _Chrome(chrome, sentAt: sentAt, sender: sender);
  }

  /// The indexes of the lines.
  final Set<int> lines;

  /// When the email carrying the receipt was sent, in local time.
  final DateTime? sentAt;

  /// The name the email came from: `Keells E-Bills`.
  final String? sender;

  static final _clock = RegExp(r'^\d{1,2}[:.]\d{2}(?!\d)');
  static final _word = RegExp('[A-Za-z]{4}');
  static final _letterOrDigit = RegExp('[A-Za-z0-9]');
  static final _forwarded = RegExp(
    r'forwarded\s+message|original\s+message',
    caseSensitive: false,
  );
  static final _emailField = RegExp(
    r'^(from|to|cc|bcc|subject|sent|reply-to|date)\s*:',
    caseSensitive: false,
  );
  static const _alwaysEmail = {'cc', 'bcc', 'subject', 'reply-to'};
  static final _address = RegExp(r'[\w.+-]+@[\w-]+\.\w');

  /// An email's `Date:` — a weekday with a comma, or a zone.
  static final _sentDate = RegExp(
    r'\b(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*,|[+-]\d{4}\b|\b(?:utc|gmt)\b',
    caseSensitive: false,
  );

  static String? _senderName(String line) {
    final name = line
        .replaceFirst(_emailField, '')
        .replaceAll(RegExp(r'<[^>]*>?'), '')
        .replaceAll(_address, '')
        .replaceAll('"', '')
        .trim();
    return RegExp('[A-Za-z]{3}').hasMatch(name) ? name : null;
  }
}
