/// The one definition of how a calendar day is written to the database.
///
/// `date` columns are fixed-width `YYYY-MM-DD` TEXT, which is what lets string
/// comparison stand in for date comparison and lets the date indexes apply. A
/// second definition of this format anywhere would be a second chance to write
/// a row that range queries silently skip.
library;

/// Formats [date] as `YYYY-MM-DD` in the **local** zone.
///
/// Local, not UTC: a transaction entered at 11pm in Colombo belongs to that
/// day, not to tomorrow in Greenwich. Any time component is dropped — a date
/// column holds a date, and the time of day is stored separately.
String encodeIsoDay(DateTime date) {
  final local = date.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Reads a `YYYY-MM-DD` column value back into a **local** midnight.
///
/// The inverse of [encodeIsoDay], and fixed-width by the same rule, so this
/// slices three fields rather than running `DateTime.parse` — which is a
/// general ISO-8601 parser built on a regular expression and costs around
/// twenty microseconds a call on the test VM. That is nothing for one row and
/// several milliseconds for the few hundred a bucketed aggregate returns,
/// which is where this was measured to matter (FR-RPT-005).
///
/// Throws [FormatException] on anything else: a date column that does not
/// hold this shape was not written by [encodeIsoDay], and a silent fallback
/// would hide a row that every range query is already skipping.
DateTime decodeIsoDay(String value) {
  if (value.length != 10 || value[4] != '-' || value[7] != '-') {
    throw FormatException('Expected YYYY-MM-DD', value);
  }
  return DateTime(
    int.parse(value.substring(0, 4)),
    int.parse(value.substring(5, 7)),
    int.parse(value.substring(8, 10)),
  );
}

/// Dart's [DateTime.monday] (1) … [DateTime.sunday] (7) as a weekday column
/// stores it: 0 = Sunday … 6 = Saturday.
///
/// The DBD numbers the week from Sunday at zero (`users.first_day_week`,
/// `recurring_rules.day_of_week`) and Dart from Monday at one, so only
/// Sunday moves; the six other days already agree. One definition, for the
/// same reason [encodeIsoDay] has one: two would be two chances to store a
/// Sunday as a Monday.
int encodeWeekdayColumn(int weekday) =>
    weekday == DateTime.sunday ? 0 : weekday;

/// The inverse of [encodeWeekdayColumn].
int decodeWeekdayColumn(int stored) => stored == 0 ? DateTime.sunday : stored;
