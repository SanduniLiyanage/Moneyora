import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';
import 'app_notification.dart';

export 'app_notification.dart';

/// The device's notification tray. FR-SET-007.
///
/// A port in `core/ports/` because two features need it and neither may
/// import the other: settings asks for the permission when the user turns
/// alerts on, and the Money Plan shows the alerts. The implementation over
/// `flutter_local_notifications` lives in `core/notifications/`, behind this
/// interface the way `TextRecogniser` stands in front of ML Kit, so every
/// use case that notifies is tested on the VM against a fake.
///
/// Showing now, and scheduling for later — the recurring reminders
/// (FR-SET-006) are the first notifications that must fire while the app
/// is closed.
abstract interface class LocalNotifier {
  /// Asks the platform for permission to notify, where it has to be asked
  /// (Android 13 and later, and iOS). True when notifications may be shown.
  ///
  /// A refusal is `Right(false)`, not a [Failure]: the user said no, and the
  /// caller decides what that means.
  Future<Either<Failure, bool>> requestPermission();

  /// Shows [notification] now, replacing any on screen with the same id.
  Future<Either<Failure, Unit>> show(AppNotification notification);

  /// Shows [notification] at [at], local wall-clock time, even if the app
  /// is closed or the phone has restarted since. FR-SET-006.
  ///
  /// Replaces anything pending under the same id. Not to the minute: the
  /// platform may batch it to save battery, which a heads-up can afford
  /// and an exact alarm would need a permission for.
  Future<Either<Failure, Unit>> schedule(
    AppNotification notification,
    DateTime at,
  );

  /// Withdraws the pending notification with [id], if there is one.
  Future<Either<Failure, Unit>> cancel(int id);

  /// The ids of every notification scheduled and not yet shown.
  Future<Either<Failure, Set<int>>> scheduledIds();
}
