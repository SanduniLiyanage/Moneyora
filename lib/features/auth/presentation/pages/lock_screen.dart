import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../injection.dart';
import '../../domain/entities/lockout_state.dart';
import '../providers/auth_providers.dart';
import '../widgets/lockout_message.dart';
import '../widgets/pin_pad.dart';

/// The screen in front of the app while it is locked. FR-SET-005,
/// NFR-SEC-003.
///
/// Drawn by `AuthGate` over the whole app, not pushed as a route: there is
/// no app bar, no back arrow and nothing to navigate to, because until the
/// PIN is right there is nowhere to go. It reads the lockout state when it
/// opens — a lockout that was running when the app was closed is still
/// counting down when it is opened again — and shows every verdict in the
/// controller's words, with the pad off while a lockout runs and back the
/// second it ends.
///
/// A correct PIN is not acted on here. `LockScreenController.submit` opens
/// the gate itself, and this screen simply stops being drawn.
class LockScreen extends ConsumerStatefulWidget {
  /// Creates the lock screen.
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _entered = '';
  bool _checking = false;
  Failure? _failure;

  Future<void> _submit() async {
    final pin = _entered;
    setState(() {
      _checking = true;
      _failure = null;
    });
    final result = await ref
        .read(lockScreenControllerProvider.notifier)
        .submit(pin);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _entered = '';
      _failure = result.fold((failure) => failure, (_) => null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lockout = ref.watch(lockScreenControllerProvider);
    final state = lockout.valueOrNull ?? LockoutState.none;
    final locked = state.isLockedAt(ref.read(clockProvider)());
    final failure = _failure ?? lockout.error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text('Enter your PIN', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                if (failure case final Failure failure)
                  SizedBox(
                    height: 40,
                    child: Center(
                      child: Text(
                        failure.message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  )
                else
                  LockoutMessage(
                    lockout: state,
                    // The state has not changed, but "locked" is a function
                    // of the clock and the pad reads it on build.
                    onExpired: () => setState(() {}),
                  ),
                const SizedBox(height: 8),
                PinPad(
                  entered: _entered,
                  enabled: !_checking && !locked && !lockout.isLoading,
                  onChanged: (value) => setState(() => _entered = value),
                  onSubmit: _submit,
                ),
                SizedBox(
                  height: 24,
                  child: _checking
                      ? const Center(
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
