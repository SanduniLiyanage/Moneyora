import '../../entities/payment_method.dart';

/// The words a receipt uses for its header fields and for every priced line
/// that is not an item: totals, discounts, tax, payments, change. FR-RCP-005.
///
/// Each list is a set of regular-expression alternatives, matched without
/// regard to case and on word boundaries. [standard] holds the words most
/// receipts print; a `ReceiptProfile` adds one shop's own with [extendedBy]
/// rather than editing these, so a quirk of one shop's printer never
/// changes how another shop's receipt reads.
///
/// The parser asks the roles in a fixed order (`ReceiptBodyReader`), so a
/// line that could be two of them is the first: `TOTAL CHANGE` is change,
/// `TOTAL VAT` is tax, `TOTAL GROSS AMOUNT` is gross, and only then is a
/// line with `total` in it the total.
class ReceiptVocabulary {
  /// Creates a vocabulary. Lists left out are empty.
  ReceiptVocabulary({
    this.merchantLabels = const [],
    this.billDateLabels = const [],
    this.timeLabels = const [],
    this.discountWords = const [],
    this.discountHeadings = const [],
    this.discountSummaries = const [],
    this.grossLabels = const [],
    this.netLabels = const [],
    this.totalLabels = const [],
    this.taxIncludedLabels = const [],
    this.taxLabels = const [],
    this.serviceLabels = const [],
    this.tenderLabels = const [],
    this.cardLabels = const [],
    this.cashLabels = const [],
    this.changeLabels = const [],
    this.pointsLabels = const [],
    this.roundingLabels = const [],
    this.countLabels = const [],
  });

  /// The words most receipts print. Not any one shop's.
  static final ReceiptVocabulary standard = ReceiptVocabulary(
    merchantLabels: const [
      r'billed\s+store',
      r'store\s*name',
      r'shop\s*name',
      r'outlet(?:\s*name)?',
      r'merchant(?:\s*name)?',
      'store',
      'shop',
    ],
    billDateLabels: const [
      r'bill(?:ed)?\s*date',
      r'(?:invoice|receipt|txn|transaction|sale|purchase)\s*date',
      'date',
    ],
    timeLabels: const [
      r'bill(?:ed)?\s*time',
      r'(?:txn|transaction|sale|print(?:ed)?)\s*time',
      'time',
    ],
    discountWords: const [
      'discount',
      'disc',
      'off',
      r'promo(?:tion)?',
      'rebate',
      'coupon',
      'voucher',
      'markdown',
    ],
    discountHeadings: const [
      r'discounts?',
      r'promotions?',
      'offers',
      'savings',
    ],
    discountSummaries: const [
      r'total\s*(?:discounts?|savings?)',
      r'discounts?\s+total',
      r'you\s+(?:have\s+)?saved',
      r'saved\s*value',
      r'sav(?:ed|ings?)',
    ],
    grossLabels: const [
      'gross',
      r'sub\s*-?\s*total',
      r'total\s+before\s+discounts?',
    ],
    netLabels: const [
      r'net\s*(?:amount|total|payable|value)',
      r'total\s+(?:net|payable)',
      r'grand\s*total',
      r'amount\s+payable',
    ],
    totalLabels: const [
      'total',
      r'amount\s+due',
      r'balance\s+due',
      r'bill\s+(?:amount|total|value)',
      r'your\s+bill',
      r'to\s+pay',
      'payable',
    ],
    taxIncludedLabels: const [
      r'incl(?:\.|uding|usive)?\s*(?:of\s*)?(?:vat|tax(?:es)?)',
    ],
    taxLabels: const ['vat', 'tax', 'gst', 'sscl', 'nbt'],
    serviceLabels: const [
      r'service\s*(?:charge|chg)',
      r'svc\s*(?:charge|chg)?',
    ],
    tenderLabels: const [
      'cash',
      'card',
      'visa',
      r'master(?:\s*card)?',
      'amex',
      'debit',
      'credit',
      'paid',
      'payment',
      r'tender(?:ed)?',
      r'lanka\s*qr',
      'cheque',
    ],
    cardLabels: const [
      'card',
      'visa',
      r'master(?:\s*card)?',
      'amex',
      'debit',
      'credit',
    ],
    cashLabels: const ['cash'],
    changeLabels: const ['change', r'balance(?!\s+due)'],
    pointsLabels: const [r'points?', 'redemption', 'redeemed'],
    roundingLabels: const [r'round(?:ing)?(?:\s*(?:off|adj(?:ustment)?))?'],
    countLabels: const [
      r'total\s*(?:items?|qty|quantity|pcs)',
      r'no\.?\s*of\s*(?:items?|qty|pcs)',
      r'^(?:qty|quantity|items?|pcs|pieces)',
    ],
  );

  /// Labels before the store's name: `Billed Store : Keells - Katubedda`.
  final List<String> merchantLabels;

  /// Labels before the date of the purchase: `Bill Date :05-Oct-2026`.
  final List<String> billDateLabels;

  /// Labels before the time of the purchase: `Billed Time :16:54:43`.
  final List<String> timeLabels;

  /// Words that make a priced line a discount, with or without its minus.
  final List<String> discountWords;

  /// Words that head a block of discount lines: `Discounts`.
  final List<String> discountHeadings;

  /// Totals of discounts already printed line by line — never applied.
  final List<String> discountSummaries;

  /// The bill before discounts: `SUB TOTAL`, `Total Gross Amount`.
  final List<String> grossLabels;

  /// The bill as paid, stated unambiguously: `NET AMOUNT`, `GRAND TOTAL`.
  final List<String> netLabels;

  /// The bill as paid, in plainer words: `TOTAL`, `AMOUNT DUE`.
  final List<String> totalLabels;

  /// A total that says the tax is inside it: `TOTAL INCL. VAT`.
  final List<String> taxIncludedLabels;

  /// Tax lines: `VAT 15%`.
  final List<String> taxLabels;

  /// Service-charge lines: `SERVICE CHARGE 10%`.
  final List<String> serviceLabels;

  /// How it was paid: `CASH`, `VISA`, `PAID`.
  final List<String> tenderLabels;

  /// The tender words that mean a card.
  final List<String> cardLabels;

  /// The tender words that mean cash.
  final List<String> cashLabels;

  /// Money handed back: `CHANGE`, `BALANCE`.
  final List<String> changeLabels;

  /// Loyalty points earned, held or spent.
  final List<String> pointsLabels;

  /// A rounding adjustment: `ROUND OFF`.
  final List<String> roundingLabels;

  /// A count of items, not a figure: `TOTAL ITEMS 5`.
  final List<String> countLabels;

  /// This vocabulary with [more]'s words added to every list.
  ReceiptVocabulary extendedBy(ReceiptVocabulary more) => ReceiptVocabulary(
    merchantLabels: [...merchantLabels, ...more.merchantLabels],
    billDateLabels: [...billDateLabels, ...more.billDateLabels],
    timeLabels: [...timeLabels, ...more.timeLabels],
    discountWords: [...discountWords, ...more.discountWords],
    discountHeadings: [...discountHeadings, ...more.discountHeadings],
    discountSummaries: [...discountSummaries, ...more.discountSummaries],
    grossLabels: [...grossLabels, ...more.grossLabels],
    netLabels: [...netLabels, ...more.netLabels],
    totalLabels: [...totalLabels, ...more.totalLabels],
    taxIncludedLabels: [...taxIncludedLabels, ...more.taxIncludedLabels],
    taxLabels: [...taxLabels, ...more.taxLabels],
    serviceLabels: [...serviceLabels, ...more.serviceLabels],
    tenderLabels: [...tenderLabels, ...more.tenderLabels],
    cardLabels: [...cardLabels, ...more.cardLabels],
    cashLabels: [...cashLabels, ...more.cashLabels],
    changeLabels: [...changeLabels, ...more.changeLabels],
    pointsLabels: [...pointsLabels, ...more.pointsLabels],
    roundingLabels: [...roundingLabels, ...more.roundingLabels],
    countLabels: [...countLabels, ...more.countLabels],
  );

  /// Any of [words], as a whole word, anywhere in a line.
  static RegExp _anywhere(List<String> words) => RegExp(
    words.isEmpty ? r'(?!)' : '\\b(?:${words.join('|')})\\b',
    caseSensitive: false,
  );

  /// A line that starts with one of [labels], then an optional `:` or `-`;
  /// group 1 is what follows.
  static RegExp _labelled(List<String> labels) => RegExp(
    labels.isEmpty
        ? r'(?!)'
        : '^(?:${labels.join('|')})\\b\\s*[:\\-]?\\s*(.*)\$',
    caseSensitive: false,
  );

  /// `Billed Store : X` — group 1 is X. A label needs its colon or dash
  /// here, so `Store Address : …` and a shop called `SHOP` are not one.
  late final RegExp merchantLabel = RegExp(
    '^(?:${merchantLabels.join('|')})\\s*[:\\-]\\s*(.+)\$',
    caseSensitive: false,
  );

  /// `Bill Date : X` — group 1 is X.
  late final RegExp billDateLabel = _labelled(billDateLabels);

  /// `Billed Time : X` — group 1 is X.
  late final RegExp timeLabel = _labelled(timeLabels);

  /// A discount word anywhere on the line.
  late final RegExp discountWord = _anywhere(discountWords);

  /// A line that opens with a discount word, after any row number, code or
  /// rate: `DISCOUNT ON TOTAL`, `2 100334 25.20% Dis`.
  late final RegExp leadingDiscount = RegExp(
    discountWords.isEmpty
        ? r'(?!)'
        : '^(?:[\\d.,%]+\\s+)*(?:${discountWords.join('|')})\\b',
    caseSensitive: false,
  );

  /// A line that is only a heading over discount lines — `Discounts`,
  /// `Nexus Deals 25%` — at most two words before the heading word.
  late final RegExp discountHeading = RegExp(
    discountHeadings.isEmpty
        ? r'(?!)'
        : '^(?:[a-z&]+\\s+){0,2}(?:${discountHeadings.join('|')})'
              '(?:\\s+\\d{1,3}(?:\\.\\d+)?\\s*%)?\\s*:?\$',
    caseSensitive: false,
  );

  /// A total of discounts.
  late final RegExp discountSummary = _anywhere(discountSummaries);

  /// The bill before discounts.
  late final RegExp gross = _anywhere(grossLabels);

  /// The bill as paid, unambiguous.
  late final RegExp net = _anywhere(netLabels);

  /// The bill as paid, plainly.
  late final RegExp total = _anywhere(totalLabels);

  /// A total that holds its tax.
  late final RegExp taxIncluded = _anywhere(taxIncludedLabels);

  /// A tax line.
  late final RegExp tax = _anywhere(taxLabels);

  /// A service charge.
  late final RegExp service = _anywhere(serviceLabels);

  /// A payment.
  late final RegExp tender = _anywhere(tenderLabels);

  /// A card payment.
  late final RegExp card = _anywhere(cardLabels);

  /// A cash payment.
  late final RegExp cash = _anywhere(cashLabels);

  /// Change handed back.
  late final RegExp change = _anywhere(changeLabels);

  /// Loyalty points.
  late final RegExp points = _anywhere(pointsLabels);

  /// A rounding adjustment.
  late final RegExp rounding = _anywhere(roundingLabels);

  /// A count of items.
  late final RegExp count = RegExp(
    countLabels.isEmpty ? r'(?!)' : '(?:${countLabels.join('|')})\\b',
    caseSensitive: false,
  );

  /// What a priced line with [label] before its figure is, when it is not
  /// an item or a discount; null when it may be either.
  ///
  /// The order is the point: points before change (`Change Money
  /// Redemption of Points`), change before the total (`Total Change`), a
  /// count before the total (`TOTAL ITEMS`), gross before net (`Total Gross
  /// Amount`), a total that holds its tax before the tax (`TOTAL INCL.
  /// VAT`), and tax before the total (`TOTAL VAT`).
  LineRole? roleOf(String label) {
    if (points.hasMatch(label)) return LineRole.points;
    if (change.hasMatch(label)) return LineRole.change;
    if (rounding.hasMatch(label)) return LineRole.rounding;
    if (discountSummary.hasMatch(label)) return LineRole.discountSummary;
    if (count.hasMatch(label)) return LineRole.count;
    // `DISCOUNT ON TOTAL BILL` is a discount that mentions the total.
    if (leadingDiscount.hasMatch(label)) return null;
    if (gross.hasMatch(label)) return LineRole.gross;
    final isTotal = net.hasMatch(label) || total.hasMatch(label);
    if (isTotal && taxIncluded.hasMatch(label)) return LineRole.net;
    if (tax.hasMatch(label)) return LineRole.tax;
    if (service.hasMatch(label)) return LineRole.service;
    if (net.hasMatch(label)) return LineRole.net;
    if (total.hasMatch(label)) return LineRole.total;
    if (tender.hasMatch(label)) return LineRole.tender;
    return null;
  }

  /// Card or cash, from a tender line; null when it names neither (`PAID
  /// 705.00`) or only the card's number.
  PaymentMethod? methodOf(String text) {
    if (cardNumber.hasMatch(text)) return null;
    if (card.hasMatch(text)) return PaymentMethod.card;
    if (cash.hasMatch(text)) return PaymentMethod.cash;
    return null;
  }

  /// Lines that are never items or headers, in any band.
  static final noise = RegExp(
    r'\b(?:tel|phone|fax|mobile|hotline|cashier|served by|www|e-?mail)\b'
    r'|[a-z0-9._-]+@[a-z0-9-]+\.[a-z]|\.com\b|\.lk\b'
    r'|\b(?:vat|tin|tax|svat)\s*(?:reg(?:istration)?|no|number|#|id)\b'
    r'|\bthank',
    caseSensitive: false,
  );

  /// Address, table and document-title lines, which sit above the first
  /// item. `TAX INVOICE` on its own line is a title, not a merchant.
  static final headerNoise = RegExp(
    r'^(?:tax\s+)?(?:invoice|receipt|bill|cash\s+(?:bill|memo))$'
    r'|\b(?:road|rd|street|st|lane|avenue|ave|mawatha|mw|place|colombo)\b'
    r'|\bno\.?\s*\d'
    r'|\b(?:table|counter|terminal|pos|pax|guests?|covers?)\b',
    caseSensitive: false,
  );

  /// A line that is nothing but column titles — three or more, so that
  /// `TOTAL` on a line of its own is still the label it is. `Oty` is how
  /// OCR reads `Qty` in a small font.
  static final columnTitles = RegExp(
    r'^(?:(?:#|ln|sn|sr|no|code|item|items|product|description|desc|'
    r'particulars|price|rate|unit|qty|oty|quantity|amount|amt|total|value|'
    r'disc|discount)[.:#]?\s*){3,}$',
    caseSensitive: false,
  );

  /// An unpriced line that says how the bill was paid — one that starts
  /// with the saying, so `CASH BILL` and `Card No` do not.
  static final paymentPrefix = RegExp(
    r'^(?:paid\s+(?:by|via|in|with|using)|payment(?:\s+(?:mode|method|type|by))?|'
    r'pay\s+(?:mode|method|type)|tender(?:ed)?(?:\s+by)?|mode\s+of\s+payment)'
    r'\s*[:\-]?\s*(?:cash|card|visa|master(?:card)?|amex|debit|credit)\b',
    caseSensitive: false,
  );

  /// `Card No : 1446`, `CARD # 4521` — the card's number, not a payment.
  static final cardNumber = RegExp(
    r'\bcard\s*(?:no|number|num|#)\b',
    caseSensitive: false,
  );
}

/// What a priced line that is not an item says about the bill.
enum LineRole {
  /// Loyalty points earned, held or spent.
  points,

  /// Money handed back.
  change,

  /// A rounding adjustment.
  rounding,

  /// A total of the discounts already printed.
  discountSummary,

  /// A count of items.
  count,

  /// The bill before discounts.
  gross,

  /// The bill as paid, stated unambiguously.
  net,

  /// The bill as paid, in plainer words.
  total,

  /// Tax or VAT.
  tax,

  /// A service charge.
  service,

  /// A payment.
  tender,
}
