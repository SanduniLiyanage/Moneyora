import 'package:flutter/material.dart';

/// The time of day as `transactions.time` stores it — `HH:MM`, 24-hour —
/// read back for a picker or a label. FR-EXP-001.
///
/// Null for no time, which is every row recorded before the entry screen
/// asked for one, and for anything that is not that shape: a time is
/// optional, so a row whose time cannot be read is shown without one
/// rather than refused.
TimeOfDay? timeOfDayFrom(String? stored) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(stored ?? '');
  if (match == null) return null;
  final hour = int.parse(match[1]!);
  final minute = int.parse(match[2]!);
  if (hour > 23 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

/// [time] in the shape `transactions.time` stores: `HH:MM`, 24-hour, so
/// rows sort by it as text.
String storedTime(TimeOfDay time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}
