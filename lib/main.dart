import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
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
    container
        .read(databaseProvider.future)
        .then(
          (_) => FlutterNativeSplash.remove(),
          // A database that fails to open is still "ready": the home screen's
          // own `_Failed` state explains it, and that screen deserves to be seen
          // rather than hidden behind a splash that never lifts.
          onError: (_, _) => FlutterNativeSplash.remove(),
        ),
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const MoneyoraApp()),
  );
}
