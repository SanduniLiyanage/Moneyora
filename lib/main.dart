import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/money_plan/presentation/providers/budget_alert_watcher.dart';
import 'features/transactions/presentation/providers/recurring_catch_up.dart';
import 'injection.dart';

/// Entry point.
///
/// `ProviderScope` wraps the whole app so every provider in `injection.dart`
/// resolves from one container. Tests replace pieces of that graph with
/// `overrides` rather than reaching for globals.
///
/// NFR-PER-001: the native launch background is normally dropped the instant
/// Flutter draws anything, spinner included — leaving a bare `AppBar` over a
/// blank body for however long the database takes to open. `preserve`/
/// `remove` hold it through that gap instead. This is scoped to `main()`
/// rather than `app.dart` on purpose: [MoneyoraApp] and its widget tests keep
/// constructing their own `ProviderScope` and know nothing about the splash,
/// so a container is built explicitly here and handed to the widget tree via
/// `UncontrolledProviderScope` — the one place a container is built by hand
/// rather than implicitly by `ProviderScope`.
void main() {
  // Required before any plugin channel is touched, and before `preserve` —
  // both need the binding ready.
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  final container = ProviderContainer();
  unawaited(
    Future.wait<void>([
      container.read(databaseProvider.future),
      // The keychain's answer to "is there a passcode?" (FR-SET-005) is a
      // few milliseconds; holding the splash for it means the first frame
      // drawn is the lock screen or the home screen, never a blank between.
      container.read(appLockProvider.future),
    ]).then(
      (_) => FlutterNativeSplash.remove(),
      // A database that fails to open is still "ready": the home screen's
      // own `_Failed` state explains it, and that screen deserves to be seen
      // rather than hidden behind a splash that never lifts.
      onError: (_, _) => FlutterNativeSplash.remove(),
    ),
  );

  // FR-SET-007: budget alerts follow every expense, whichever screen it was
  // entered on, so the watcher lives as long as the app does. Started here
  // rather than in `MoneyoraApp` for the reason the splash is: the app's
  // widget tests build their own scope and have no plan to watch.
  container.listen(budgetAlertWatcherProvider, (_, _) {});

  // FR-EXP-008, FR-INC-004: recurring entries that fell due while the app
  // was closed or in the background are posted on launch and on every
  // resume. App-lifetime for the same reason as the watcher above.
  container.listen(recurringCatchUpProvider, (_, _) {});

  runApp(
    UncontrolledProviderScope(container: container, child: const MoneyoraApp()),
  );
}
