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
/// Showing only, for now. Scheduling arrives with the recurring reminders
/// that need it (FR-SET-006), not ahead of them.
abstract interface class LocalNotifier {
  /// Asks the platform for permission to notify, where it has to be asked
  /// (Android 13 and later, and iOS). True when notifications may be shown.
  ///
  /// A refusal is `Right(false)`, not a [Failure]: the user said no, and the
  /// caller decides what that means.
  Future<Either<Failure, bool>> requestPermission();

  /// Shows [notification] now, replacing any on screen with the same id.
  Future<Either<Failure, Unit>> show(AppNotification notification);
}
