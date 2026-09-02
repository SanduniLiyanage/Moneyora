import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Entry point.
///
/// `ProviderScope` wraps the whole app so every provider in `injection.dart`
/// resolves from one container. Tests replace pieces of that graph with
/// `overrides` rather than reaching for globals.
void main() {
  // Required before any plugin channel is touched. The database opens through
  // a platform channel during the first frame, and without this the binding
  // is not ready when it does.
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ProviderScope(child: MoneyoraApp()));
}
