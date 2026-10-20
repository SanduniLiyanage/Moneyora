import 'package:equatable/equatable.dart';

import 'debt.dart';

/// [name] in the form people are matched by: trimmed, lower case, one
/// space between words. "Nimal", " nimal " and "NIMAL" are one person;
/// "Nimal P." is another until the user says otherwise (FR-DBT-006).
/// FR-DBT-005, E-47.
String personKey(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// One person and every debt recorded with them, netted. FR-DBT-005, E-47.
///
/// Derived from the rows as they are, never stored: grouping needs no
/// migration, and the records stay as they were written, each still
/// marked paid, changed or deleted on its own (FR-DBT-003).
class DebtPerson extends Equatable {
  /// Creates a person over [records], which must all share one
  /// [personKey]. Screens use [DebtPerson.group].
  const DebtPerson({required this.name, required this.records});

  /// How the person is written: as on most of their records, the first
  /// written breaking a tie. Rename (FR-DBT-006) is how it changes.
  final String name;

  /// Their records, in the list's order: open ones first, soonest due
  /// first, then paid ones, most recently paid first.
  final List<Debt> records;

  /// [name], matched as [personKey] matches it.
  String get key => personKey(name);

  /// The records still counted.
  List<Debt> get open => [
    for (final d in records)
      if (d.isOpen) d,
  ];

  /// The records already settled.
  List<Debt> get paid => [
    for (final d in records)
      if (!d.isOpen) d,
  ];

  /// Whether anything is still open with them.
  bool get hasOpen => records.any((d) => d.isOpen);

  /// What they owe the user, less what the user owes them, over the open
  /// records: positive when they owe the user, negative when the user owes
  /// them, zero when the two are square. A new record either way offsets
  /// what is already there, so Rs1,000 owed to the user and Rs400 owed by
  /// them is Rs600 owed to the user.
  int get netCents {
    var net = 0;
    for (final debt in records) {
      if (!debt.isOpen) continue;
      net += debt.direction == DebtDirection.owedToMe
          ? debt.amountCents
          : -debt.amountCents;
    }
    return net;
  }

  /// The soonest due day among the open records, or null when none has one.
  DateTime? get soonestDue {
    DateTime? soonest;
    for (final debt in records) {
      final due = debt.dueOn;
      if (!debt.isOpen || due == null) continue;
      if (soonest == null || due.isBefore(soonest)) soonest = due;
    }
    return soonest;
  }

  /// Whether, on [today], something is still owed and a record behind it is
  /// past its due day: a record running the way the net runs, so a debt
  /// the user owes is not called overdue on someone who owes the user more.
  bool isOverdue(DateTime today) {
    final net = netCents;
    if (net == 0) return false;
    final way = net > 0 ? DebtDirection.owedToMe : DebtDirection.iOwe;
    return records.any((d) => d.direction == way && d.isOverdue(today));
  }

  /// [debts] grouped by person, in the order the list shows them: people
  /// with something open first — overdue ones first, then by the soonest
  /// due day, then the most owed either way — and then people with
  /// nothing open, most recently settled first. Each person keeps their
  /// records in the order [debts] had them.
  static List<DebtPerson> group(
    Iterable<Debt> debts, {
    required DateTime today,
  }) {
    final byKey = <String, List<Debt>>{};
    for (final debt in debts) {
      byKey.putIfAbsent(personKey(debt.person), () => []).add(debt);
    }

    final people = [
      for (final records in byKey.values)
        DebtPerson(name: _usualName(records), records: records),
    ];
    final overdue = {
      for (final p in people)
        if (p.isOverdue(today)) p.key,
    };

    int compare(DebtPerson a, DebtPerson b) {
      if (a.hasOpen != b.hasOpen) return a.hasOpen ? -1 : 1;
      if (!a.hasOpen) return _lastPaid(b).compareTo(_lastPaid(a));
      final late = overdue.contains(a.key);
      if (late != overdue.contains(b.key)) return late ? -1 : 1;
      final dueA = a.soonestDue;
      final dueB = b.soonestDue;
      if (dueA != dueB) {
        if (dueA == null) return 1;
        if (dueB == null) return -1;
        return dueA.compareTo(dueB);
      }
      final size = b.netCents.abs().compareTo(a.netCents.abs());
      if (size != 0) return size;
      return a.key.compareTo(b.key);
    }

    return people..sort(compare);
  }

  /// Every person recorded, as the list names them, for the form to
  /// suggest: one spelling each. FR-DBT-006.
  static List<String> names(Iterable<Debt> debts) {
    final byKey = <String, List<Debt>>{};
    for (final debt in debts) {
      byKey.putIfAbsent(personKey(debt.person), () => []).add(debt);
    }
    return [for (final records in byKey.values) _usualName(records)]
      ..sort((a, b) => personKey(a).compareTo(personKey(b)));
  }

  /// The spelling most of [records] use, the earliest written breaking a
  /// tie: a person first saved as "Nimal" is not renamed "nimal" by one
  /// record typed in a hurry.
  static String _usualName(List<Debt> records) {
    final count = <String, int>{};
    final first = <String, Debt>{};
    for (final debt in records) {
      final name = debt.person.trim();
      count[name] = (count[name] ?? 0) + 1;
      final seen = first[name];
      if (seen == null || _writtenBefore(debt, seen)) first[name] = debt;
    }
    String? best;
    for (final name in count.keys) {
      if (best == null ||
          count[name]! > count[best]! ||
          (count[name] == count[best] &&
              _writtenBefore(first[name]!, first[best]!))) {
        best = name;
      }
    }
    return best!;
  }

  /// Whether [a] was begun before [b], the one saved first on the same day.
  static bool _writtenBefore(Debt a, Debt b) {
    final day = a.incurredOn.compareTo(b.incurredOn);
    return day < 0 || (day == 0 && (a.id ?? 0) < (b.id ?? 0));
  }

  static DateTime _lastPaid(DebtPerson person) {
    var last = DateTime(0);
    for (final debt in person.records) {
      final paid = debt.paidOn;
      if (paid != null && paid.isAfter(last)) last = paid;
    }
    return last;
  }

  @override
  List<Object?> get props => [name, records];
}
