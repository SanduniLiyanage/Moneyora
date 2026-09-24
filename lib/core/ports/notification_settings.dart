import 'package:equatable/equatable.dart';

/// Which notifications the user has turned on. FR-SET-007.
///
/// From the `users` row, read by the Money Plan, which may not import the
/// settings feature that owns the row (rule 4 of `check_architecture.sh`) —
/// so the value lives here, as [CalendarSettings] does, and
/// [NotificationSettingsReader] is the seam.
class NotificationSettings extends Equatable {
  /// Creates the settings.
  const NotificationSettings({this.budgetAlertsEnabled = false});

  /// The schema's column defaults: everything off.
  ///
  /// Off because turning a notification on is where the platform's
  /// permission is asked for, and a permission prompt belongs to the moment
  /// the user chose the thing it is for — not to a launch that did not.
  static const NotificationSettings defaults = NotificationSettings();

  /// Whether a category crossing 80% and 100% of its plan allocation is
  /// announced. FR-SET-007.
  final bool budgetAlertsEnabled;

  @override
  List<Object?> get props => [budgetAlertsEnabled];
}
