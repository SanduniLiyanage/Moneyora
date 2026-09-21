import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/lock_screen.dart';
import '../providers/auth_providers.dart';

/// Puts the lock screen in front of the whole app. FR-SET-005.
///
/// Sits in `MaterialApp.router`'s `builder`, around the Navigator, rather
/// than being a route in it. Three things follow. A deep link, a restored
/// route or anything else the router does lands *behind* the gate, because
/// there is no route the gate is not in front of. Locking on resume covers
/// whatever screen is current without touching the navigation stack — the
/// Navigator stays in the tree, offstage, and comes back exactly as it was.
/// And the router knows nothing about auth: no redirect, no refresh
/// listenable, no route that a typo could leave unguarded.
///
/// Offstage rather than removed, on purpose: removing the Navigator would
/// dispose every screen's state — a half-typed expense, a scroll position —
/// on each lock. `Offstage` neither paints nor hit-tests, `ExcludeFocus`
/// keeps a hardware keyboard from typing into it, and the lock screen is
/// opaque over the top. The device's back button is swallowed while locked,
/// or it would pop the offstage stack out of sight.
///
/// Lifecycle: `paused` locks (see `relockGrace` for why not `inactive`) and
/// `resumed` unlocks again if the pause was short.
class AuthGate extends ConsumerStatefulWidget {
  /// Wraps [child] — the Navigator — in the gate.
  const AuthGate({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(appLockProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
        unawaited(controller.didPause());
      case AppLifecycleState.resumed:
        controller.didResume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Future<bool> didPopRoute() async {
    // Registered before the Router's own dispatcher — this widget is its
    // parent — so this answer is asked for first. `true` is "handled": the
    // press goes no further.
    return ref.read(appLockProvider.notifier).isLocked;
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final unlocked = lock.valueOrNull == false;

    return Stack(
      children: [
        ExcludeFocus(
          excluding: !unlocked,
          child: Offstage(offstage: !unlocked, child: widget.child),
        ),
        if (!unlocked)
          lock.isLoading
              // The launch frame, before the keychain has answered.
              ? ColoredBox(color: Theme.of(context).colorScheme.surface)
              // Its own Overlay: the lock screen is outside the Navigator,
              // which is where a MaterialApp's overlay normally comes from,
              // and a tooltip or a menu has nowhere to draw without one.
              : Overlay(
                  initialEntries: [
                    OverlayEntry(builder: (_) => const LockScreen()),
                  ],
                ),
      ],
    );
  }
}
