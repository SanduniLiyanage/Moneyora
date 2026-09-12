import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/category_total.dart';
import '../entities/spending_query.dart';

/// A closed period to report over, both ends **inclusive** whole days.
///
/// Inclusive at both ends because that is how a person says it — "the first to
/// the thirty-first of August" — and an exclusive end silently drops the last
/// day's spending, which is a wrong answer that looks plausible.
class DateRange extends Equatable {
  /// Creates a range from [from] to [to], inclusive.
  const DateRange({required this.from, required this.to});

  /// The whole of one calendar month.
  ///
  /// Here rather than at each call site because the last day of a month is
  /// `DateTime(year, month + 1, 0)` — correct, and unmemorable enough that
  /// every rediscovery of it is a chance to write `30` and be wrong four times
  /// a year.
  factory DateRange.month(int year, int month) =>
      DateRange(from: DateTime(year, month), to: DateTime(year, month + 1, 0));

  /// The single calendar day [date] falls on. FR-RPT-002's "Day".
  ///
  /// Both ends are the same midnight: the range is inclusive, and the
  /// datasource compares `YYYY-MM-DD` strings, so a time component on either
  /// end would be noise at best and a dropped row at worst.
  factory DateRange.day(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    return DateRange(from: start, to: start);
  }

  /// The whole week [date] falls in. FR-RPT-002's "Week".
  ///
  /// [firstWeekday] is a `DateTime` weekday constant and defaults to Monday.
  /// It is a parameter rather than a constant because FR-SET-004 makes the
  /// first day of the week user-configurable (Sunday/Monday) in Sprint 7;
  /// until that setting exists there is one caller and it passes the default.
  factory DateRange.week(DateTime date, {int firstWeekday = DateTime.monday}) {
    final start = DateTime(date.year, date.month, date.day);
    // `weekday` is 1..7 Monday-first, so the offset back to the chosen first
    // day is modulo 7 rather than a subtraction that can go negative.
    final offset = (start.weekday - firstWeekday + 7) % 7;
    final from = start.subtract(Duration(days: offset));
    return DateRange(from: from, to: from.add(const Duration(days: 6)));
  }

  /// The whole of one calendar year. FR-RPT-002's "Year".
  factory DateRange.year(int year) =>
      DateRange(from: DateTime(year), to: DateTime(year, 12, 31));

  /// Every dated row the app can hold. FR-RPT-002's "All".
  ///
  /// A closed range rather than a nullable one, so "All" costs no branch in
  /// the query, the repository or the use case — the same `date >= ? AND
  /// date <= ?` runs, still on the index. The floor is the year the app's own
  /// date pickers already start at, and the ceiling is far enough out that a
  /// future-dated transaction is still inside it.
  factory DateRange.allTime() =>
      DateRange(from: DateTime(2000), to: DateTime(2100, 12, 31));

  /// First day of the period.
  final DateTime from;

  /// Last day of the period.
  final DateTime to;

  /// True when the range runs backwards.
  bool get isInverted => from.isAfter(to);

  @override
  List<Object?> get props => [from, to];
}

/// Reads over transaction history. No writes: analytics never changes a row.
abstract class AnalyticsRepository {
  /// Totals expense spending per category over [query]'s period, largest
  /// first, for one account or for all of them (FR-RPT-003).
  ///
  /// Transfers are excluded (E-02) and split parts are counted against their
  /// own categories rather than the parent's (E-04).
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    SpendingQuery query,
  );

  /// Totals income over [range]. FR-COP-008.
  ///
  /// Income is never split (E-04's split table exists for FR-EXP-010's
  /// expenses only), so this is a plain sum with no union to write.
  Future<Either<Failure, int>> incomeForPeriod(DateRange range);
}
