import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../injection.dart';
import '../../domain/entities/lockout_policy.dart';
import '../../domain/entities/lockout_state.dart';

/// What to tell the user about where the gate stands. NFR-SEC-003.
///
/// Three sentences. Nothing, while no attempt has failed. "Wrong PIN. N
/// attempts left." once one has — the count from [LockoutPolicy], so the
/// screen never says a number the use case would not honour. And during a
/// lockout, a countdown that ticks once a second off [clockProvider] and
/// reports [onExpired] when it reaches zero, so the pad can come back
/// without the user having to press something to find out.
///
/// The ticker is a real [Timer]; the *time* is the provider's, so a test
/// can pump a second and move the clock a second and see the same thing a
/// user would.
class LockoutMessage extends ConsumerStatefulWidget {
  /// Creates the message for [lockout].
  const LockoutMessage({
    required this.lockout,
    this.onExpired,
    this.policy = LockoutPolicy.standard,
    super.key,
  });

  /// Where the gate stands.
  final LockoutState lockout;

  /// Called once, when a running lockout ends.
  final VoidCallback? onExpired;

  /// The policy that says how many attempts are left.
  final LockoutPolicy policy;

  /// The sentence for [lockout] at [now], or null when there is nothing to
  /// say. Shared with the flow page so both say it the same way.
  static String? sentence(
    LockoutState lockout,
    DateTime now, {
    LockoutPolicy policy = LockoutPolicy.standard,
  }) {
    if (lockout.isLockedAt(now)) {
      return 'Too many attempts. Try again in '
          '${_clock(lockout.remainingAt(now))}.';
    }
    if (lockout.failedAttempts == 0) return null;
    final left = policy.attemptsBeforeLockout(lockout);
    return 'Wrong PIN. $left ${left == 1 ? 'attempt' : 'attempts'} left.';
  }

  /// "27 s", "1:05", "59:59", "1:00:00".
  static String _clock(Duration remaining) {
    // Round up: a lockout with 0.4 s left is not over yet.
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    if (seconds < 60) return '$seconds s';
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    if (minutes < 60) return '$minutes:$rest';
    final hours = minutes ~/ 60;
    final restMinutes = (minutes % 60).toString().padLeft(2, '0');
    return '$hours:$restMinutes:$rest';
  }

  @override
  ConsumerState<LockoutMessage> createState() => _LockoutMessageState();
}

class _LockoutMessageState extends ConsumerState<LockoutMessage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(LockoutMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lockout != widget.lockout) _sync();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Runs the ticker while there is a lockout to count down, and only then.
  void _sync() {
    _ticker?.cancel();
    _ticker = null;
    if (!widget.lockout.isLockedAt(ref.read(clockProvider)())) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = ref.read(clockProvider)();
      setState(() {});
      if (!widget.lockout.isLockedAt(now)) {
        _ticker?.cancel();
        _ticker = null;
        widget.onExpired?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = ref.read(clockProvider)();
    final text = LockoutMessage.sentence(
      widget.lockout,
      now,
      policy: widget.policy,
    );
    // Reserve the line so the pad does not jump when a sentence appears.
    return SizedBox(
      height: 40,
      child: Center(
        child: text == null
            ? null
            : Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
      ),
    );
  }
}
