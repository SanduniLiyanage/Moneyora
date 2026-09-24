/// Notifications the user tapped, as the payload each carried. FR-SET-007.
///
/// Apart from [LocalNotifier] because nothing in a domain layer needs it:
/// what a tap opens is the app root's business — it holds the router — and
/// a use case that announces an alert has no reason to know it was read.
/// The same object implements both.
abstract interface class NotificationTaps {
  /// The payload of the notification that launched the app from cold, or
  /// null when the app was opened some other way. Asked once, at start.
  Future<String?> launchPayload();

  /// The payload of each notification tapped while the app is running.
  Stream<String> get opened;
}
