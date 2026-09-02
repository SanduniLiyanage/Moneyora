import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// The root widget: theming plus routing, and nothing else.
///
/// `themeMode` follows the system for now. FR-SET-001 requires a user toggle,
/// which arrives in Sprint 7 with the rest of Settings and will read from the
/// `users.theme` column the schema already carries.
class MoneyoraApp extends StatefulWidget {
  /// Creates the app.
  const MoneyoraApp({super.key});

  @override
  State<MoneyoraApp> createState() => _MoneyoraAppState();
}

class _MoneyoraAppState extends State<MoneyoraApp> {
  // Built once and held. GoRouter owns navigation history, so rebuilding it
  // on every widget rebuild would silently reset the back stack.
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Moneyora',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
