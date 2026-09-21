import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/widgets/auth_gate.dart';
import 'features/settings/presentation/providers/settings_providers.dart';

/// The root widget: theming, routing and the passcode gate, and nothing
/// else.
///
/// `themeMode` is the user's choice, read live from the `users.theme` column
/// through `themeModeProvider` (FR-SET-001), so a change made on the settings
/// screen is drawn by every screen beneath it without a restart. Until the
/// stored choice is known it follows the device.
///
/// `builder` wraps the Navigator in [AuthGate] (FR-SET-005), which is what
/// puts the lock screen in front of every route rather than making it one —
/// see the gate for why. It sits below the theme, so the lock screen is
/// drawn in the user's colours.
class MoneyoraApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const MoneyoraApp({super.key});

  @override
  ConsumerState<MoneyoraApp> createState() => _MoneyoraAppState();
}

class _MoneyoraAppState extends ConsumerState<MoneyoraApp> {
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
      themeMode: ref.watch(themeModeProvider),
      routerConfig: _router,
      builder: (context, child) =>
          AuthGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
