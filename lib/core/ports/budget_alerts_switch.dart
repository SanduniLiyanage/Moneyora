import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// Turns FR-SET-007's budget alerts on, from outside `features/settings/`.
///
/// The Money Plan offers alerts at the moment they matter — when a plan is
/// saved and starts being tracked — rather than leaving them to be found in
/// Settings. The settings feature owns the row and the permission prompt;
/// its `SetBudgetAlerts` fulfils this, and `injection.dart` hands it out, so
/// neither feature imports the other (`check_architecture.sh` rule 4).
abstract interface class BudgetAlertsSwitch {
  /// Asks the platform for permission and, if given, turns alerts on. A
  /// refusal is a `PermissionFailure` saying where the permission now is.
  Future<Either<Failure, Unit>> turnOn();
}
