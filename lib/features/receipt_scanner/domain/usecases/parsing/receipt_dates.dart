/// Dates and times as receipts print them. FR-RCP-005.
///
/// - **Dates are day-first.** `03/04/2026` is 3 April: Sri Lankan receipts
///   print `dd/mm/yyyy`, and the ISO form is unambiguous either way. A
///   two-digit year is this century. `05-Oct-2026` and `12 Mar 2026` are
///   read too.
/// - **A time is 24-hour unless it says AM or PM**, with its seconds when
///   printed. An impossible one is no time at all.
/// - **A zone is honoured only where one is printed.** A receipt prints
///   the shop's local time and no zone; an email header prints UTC with
///   `+0000`, and that is turned to local time before it is used.
abstract final class ReceiptDates {
  static final _numericDate = RegExp(
    r'(?<!\d)(\d{1,2})[/.-](\d{1,2})[/.-](\d{4}|\d{2})(?!\d)',
  );
  static final _isoDate = RegExp(r'(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)');
  static final _wordDate = RegExp(
    r'(?<!\d)(\d{1,2})[\s.-]*'
    r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*'
    r'[\s.,-]*(\d{4}|\d{2})(?!\d)',
    caseSensitive: false,
  );
  static final _time = RegExp(
    r'(?<!\d)(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?(?![\d:])',
    caseSensitive: false,
  );

  /// `+0000`, `+05:30`, `UTC`, `GMT` — the zone an email header prints.
  static final _zone = RegExp(
    r'(?:^|\s)([+-])(\d{2}):?(\d{2})\b|\b(?:utc|gmt)\b',
    caseSensitive: false,
  );

  static const _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// The date on [line], with its time when one follows, or null.
  static DateTime? dateOf(String line) {
    int year, month, day;
    if (_isoDate.firstMatch(line) case final m?) {
      year = int.parse(m[1]!);
      month = int.parse(m[2]!);
      day = int.parse(m[3]!);
    } else if (_numericDate.firstMatch(line) case final m?) {
      day = int.parse(m[1]!);
      month = int.parse(m[2]!);
      year = _fourDigit(m[3]!);
    } else if (_wordDate.firstMatch(line) case final m?) {
      day = int.parse(m[1]!);
      month = _months.indexOf(m[2]!.substring(0, 3).toLowerCase()) + 1;
      year = _fourDigit(m[3]!);
    } else {
      return null;
    }

    final (hour, minute, second) = timeOf(line) ?? (0, 0, 0);
    final date = DateTime(year, month, day, hour, minute, second);
    // DateTime normalises 31/02 into March; a printed date must not.
    if (date.month != month || date.day != day) return null;
    return date;
  }

  /// The time on [line] — `16:54:43`, `05:12 PM` — or null.
  static (int, int, int)? timeOf(String line) {
    final t = _time.firstMatch(line);
    if (t == null) return null;
    var hour = int.parse(t[1]!);
    final minute = int.parse(t[2]!);
    final second = t[3] == null ? 0 : int.parse(t[3]!);
    final meridiem = t[4]?.toLowerCase();
    if (meridiem == 'pm' && hour < 12) hour += 12;
    if (meridiem == 'am' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59 || second > 59) return null;
    return (hour, minute, second);
  }

  /// [date] with the time of day [time].
  static DateTime at(DateTime date, (int, int, int) time) =>
      DateTime(date.year, date.month, date.day, time.$1, time.$2, time.$3);

  /// The date and time on [line] in local time, when [line] prints the
  /// zone it was written in; as printed when it prints none. [localOffset]
  /// is the device's offset from UTC — the clock's own when null.
  static DateTime? zonedDateOf(String line, {Duration? localOffset}) {
    final printed = dateOf(line);
    if (printed == null) return null;
    final zone = _zone.firstMatch(line);
    if (zone == null) return printed;
    final offset = zone[1] == null
        ? Duration.zero
        : Duration(hours: int.parse(zone[2]!), minutes: int.parse(zone[3]!)) *
              (zone[1] == '-' ? -1 : 1);
    final utc = DateTime.utc(
      printed.year,
      printed.month,
      printed.day,
      printed.hour,
      printed.minute,
      printed.second,
    ).subtract(offset);
    final local = localOffset == null ? utc.toLocal() : utc.add(localOffset);
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
  }

  static int _fourDigit(String year) =>
      year.length == 4 ? int.parse(year) : 2000 + int.parse(year);
}
