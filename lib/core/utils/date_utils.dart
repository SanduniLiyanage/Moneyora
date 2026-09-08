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
