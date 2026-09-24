/// [LocalNotifier] and [NotificationTaps] over `flutter_local_notifications`.
/// FR-SET-007.
///
/// The one file that knows how the platform is asked. Never unit-tested — a
/// method channel does not answer in a VM test, the way ML Kit's and
/// `local_auth`'s do not — so it holds no decision beyond the translation:
/// every use case that notifies is tested against a fake of the port, and
/// this is verified on the emulator.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';
import '../ports/local_notifier.dart';
import '../ports/notification_taps.dart';

/// The platform's notification tray.
class FlutterLocalNotifier implements LocalNotifier, NotificationTaps {
  /// Creates the notifier over the plugin's one instance.
  FlutterLocalNotifier() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _opened = StreamController.broadcast();
  Future<void>? _initialised;

  /// Initialises the plugin once, however many callers arrive first.
  ///
  /// **No permission is asked here.** The Darwin defaults request alert,
  /// sound and badge permission during initialisation, which would put the
  /// prompt in front of every iOS user at launch; permission is asked by
  /// [requestPermission], when the user turns alerts on (E-35). Android
  /// never asks during initialisation.
  Future<void> _ensureInitialised() => _initialised ??= _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      ),
    ),
    onDidReceiveNotificationResponse: (response) {
      if (response.payload case final payload?) _opened.add(payload);
    },
  );

  @override
  Future<Either<Failure, bool>> requestPermission() async {
    try {
      await _ensureInitialised();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        // Below Android 13 there is no runtime permission: the answer is
        // whether notifications are enabled for the app at all.
        return Right(await android.requestNotificationsPermission() ?? false);
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return Right(
          await ios.requestPermissions(alert: true, sound: true) ?? false,
        );
      }
      return const Right(false);
    } on Exception catch (e) {
      debugPrint('[notifications] permission request failed: $e');
      return const Left(
        PermissionFailure('Could not ask for permission to notify.'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> show(AppNotification notification) async {
    try {
      await _ensureInitialised();
      await _plugin.show(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        notificationDetails: _detailsFor(notification.kind),
        payload: notification.payload,
      );
      return const Right(unit);
    } on Exception catch (e) {
      debugPrint('[notifications] show failed: $e');
      return const Left(PermissionFailure('Could not show a notification.'));
    }
  }

  @override
  Future<String?> launchPayload() async {
    try {
      await _ensureInitialised();
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return details.notificationResponse?.payload;
    } on MissingPluginException {
      // No platform beneath: a widget test, or a desktop run. Nothing
      // launched the app from a notification.
      return null;
    } on Exception catch (e) {
      debugPrint('[notifications] launch details unavailable: $e');
      return null;
    }
  }

  @override
  Stream<String> get opened => _opened.stream;

  /// The channel and presentation for [kind].
  ///
  /// The channel's id is stable across releases — Android keeps the user's
  /// choices against it — and its name and description are what the phone's
  /// settings show beside the switch that silences it.
  static NotificationDetails _detailsFor(NotificationKind kind) =>
      switch (kind) {
        NotificationKind.budgetAlert => const NotificationDetails(
          android: AndroidNotificationDetails(
            'budget_alerts',
            'Budget alerts',
            channelDescription:
                'When a category of your active plan reaches 80% or 100% '
                'of its budget.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          // Shown while the app is open too: the expense that crossed the
          // threshold was most likely just entered in it.
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
          ),
        ),
      };
}
