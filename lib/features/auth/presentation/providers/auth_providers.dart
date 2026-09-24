/// Presentation state for the passcode gate.
///
/// These talk to **use cases**, never to a repository or a datasource, which
/// is the rule `scripts/check_architecture.sh` enforces and the reason the
/// lock screen can be tested by overriding one provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../injection.dart';
import '../../domain/entities/lockout_state.dart';
import '../../domain/entities/pin_verdict.dart';
import '../../domain/usecases/change_passcode.dart';

/// Whether a passcode is set. FR-SET-005.
///
/// Read at launch by [AppLockController] and by the settings screen for
/// which rows to offer. Invalidated by [PasscodeController] after every
/// write, since the keychain has no change bus to listen to.
final passcodeEnabledProvider = FutureProvider<bool>((ref) async {
  final hasPasscode = ref.watch(hasPasscodeProvider);
  final result = await hasPasscode(const NoParams());
  // The error channel, not a throw: a Failure is a value, as
  // `spendingByCategoryTotalsProvider` records.
  return result.match(Future<bool>.error, Future<bool>.value);
});

/// How long the app may be in the background before it locks again.
///
/// Thirty seconds rather than at once, because opening the camera to scan a
/// receipt (FR-RCP-002) pauses the app the same way switching away does, and
/// a lock screen between the photo and the review would break the feature
/// the app exists for. The app *does* lock the moment it is paused — that is
/// what the task switcher's snapshot shows — and unlocks itself on return
/// inside the grace; what the grace buys is not showing the PIN pad to
/// someone who was gone ten seconds.
const Duration relockGrace = Duration(seconds: 30);

/// Whether the lock screen is in front of the app. FR-SET-005.
///
/// `true` is locked. Loading is the launch, before the keychain has said
/// whether there is a passcode at all; the gate draws nothing over the app
/// for that frame rather than a lock screen that might not be needed.
///
/// A keychain that cannot be read resolves to *unlocked*. That is the
/// fail-open choice, made on purpose: the passcode never protects the data
/// (E-31 §1), the database key lives in the same keychain and will have
/// failed too, so the home screen's own "could not open" state is what the
/// user sees either way — and a lock screen no PIN can pass would be a
/// brick, not a lock.
class AppLockController extends AsyncNotifier<bool> {
  DateTime? _pausedAt;
  bool _lockedByPause = false;

  @override
  Future<bool> build() async {
    // read, not watch: a passcode set or removed on the settings screen
    // invalidates [passcodeEnabledProvider], and rebuilding here on that
    // would lock the app in the user's hands the moment they set a PIN.
    try {
      return await ref.read(passcodeEnabledProvider.future);
    } on Failure {
      return false;
    }
  }

  /// Whether the gate is closed right now.
  bool get isLocked => state.valueOrNull ?? false;

  /// Lets the app through. Called by the lock screen on a correct PIN.
  void unlock() {
    _lockedByPause = false;
    state = const AsyncValue.data(false);
  }

  /// Closes the gate. Only when a passcode is set.
  Future<void> lock() async {
    if (!await _passcodeEnabled()) return;
    _lockedByPause = false;
    state = const AsyncValue.data(true);
  }

  /// The app went to the background. Locks at once, remembering when.
  Future<void> didPause() async {
    if (!await _passcodeEnabled()) return;
    _pausedAt = ref.read(clockProvider)();
    if (!isLocked) {
      _lockedByPause = true;
      state = const AsyncValue.data(true);
    }
  }

  /// The app came back. Undoes a pause-lock that is within the grace.
  ///
  /// A lock set any other way — the launch, a lock screen the user was
  /// already looking at when they left — stays.
  void didResume() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (!_lockedByPause || pausedAt == null) return;
    final away = ref.read(clockProvider)().difference(pausedAt);
    if (away < relockGrace) unlock();
    _lockedByPause = false;
  }

  Future<bool> _passcodeEnabled() async {
    try {
      return await ref.read(passcodeEnabledProvider.future);
    } on Failure {
      return false;
    }
  }
}

/// Whether the lock screen is in front of the app.
final appLockProvider = AsyncNotifierProvider<AppLockController, bool>(
  AppLockController.new,
);

/// The lock screen's attempt. FR-SET-005, NFR-SEC-003.
///
/// State is where the gate stands, so the screen can show a lockout that
/// was already running when it opened. [submit] returns the verdict — or the
/// failure, for its sentence — and opens the gate itself on [PinAccepted],
/// so a screen cannot draw the wrong conclusion from a verdict.
class LockScreenController extends AutoDisposeAsyncNotifier<LockoutState> {
  @override
  Future<LockoutState> build() async {
    final getLockout = ref.watch(getLockoutStateProvider);
    final result = await getLockout(const NoParams());
    return result.match(Future<LockoutState>.error, Future<LockoutState>.value);
  }

  /// Checks [pin].
  Future<Either<Failure, PinVerdict>> submit(String pin) async {
    final verify = ref.read(verifyPasscodeProvider);
    final result = await verify(pin);
    result.match(
      (failure) => state = AsyncValue.error(failure, StackTrace.current),
      (verdict) => switch (verdict) {
        PinAccepted() => ref.read(appLockProvider.notifier).unlock(),
        PinRejected(:final lockout) ||
        PinLockedOut(:final lockout) => state = AsyncValue.data(lockout),
      },
    );
    return result;
  }

  /// Attempts biometric unlock, showing [reason] on the OS prompt.
  ///
  /// Bypasses the lockout entirely — it is not `VerifyPasscode`, and does
  /// not touch [LockoutState] — because the lockout defends the PIN alone;
  /// the sensor is the OS's to rate-limit. A failed or declined prompt
  /// leaves the screen exactly as it was, the same as a PIN not yet typed.
  Future<void> unlockWithBiometrics(String reason) async {
    final authenticate = ref.read(authenticateWithBiometricsProvider);
    final result = await authenticate(reason);
    result.match((_) {}, (ok) {
      if (ok) ref.read(appLockProvider.notifier).unlock();
    });
  }
}

/// Controller for the lock screen.
final lockScreenControllerProvider =
    AutoDisposeAsyncNotifierProvider<LockScreenController, LockoutState>(
      LockScreenController.new,
    );

/// Setting, changing and removing the passcode. FR-SET-005.
///
/// Each returns what its use case returned, for the sentence or the
/// verdict, and refreshes [passcodeEnabledProvider] after a write so the
/// settings screen's rows follow.
class PasscodeController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Turns the passcode on.
  Future<Failure?> set(String pin) async {
    state = const AsyncValue<void>.loading();
    final result = await ref.read(setPasscodeProvider)(pin);
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return failure;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        ref.invalidate(passcodeEnabledProvider);
        return null;
      },
    );
  }

  /// Replaces the passcode, on proof of the current one.
  Future<Either<Failure, PinVerdict>> change({
    required String current,
    required String next,
  }) async {
    state = const AsyncValue<void>.loading();
    final result = await ref.read(changePasscodeProvider)(
      ChangePasscodeParams(current: current, next: next),
    );
    return _settle(result);
  }

  /// Turns the passcode off, on proof of it.
  Future<Either<Failure, PinVerdict>> remove(String current) async {
    state = const AsyncValue<void>.loading();
    final result = await ref.read(removePasscodeProvider)(current);
    return _settle(result);
  }

  Either<Failure, PinVerdict> _settle(Either<Failure, PinVerdict> result) {
    result.match(
      (failure) => state = AsyncValue<void>.error(failure, StackTrace.current),
      (verdict) {
        state = const AsyncValue<void>.data(null);
        if (verdict is PinAccepted) ref.invalidate(passcodeEnabledProvider);
      },
    );
    return result;
  }
}

/// Controller for the passcode rows on the settings screen.
final passcodeControllerProvider =
    AutoDisposeAsyncNotifierProvider<PasscodeController, void>(
      PasscodeController.new,
    );

/// Whether biometric unlock is turned on. NFR-SEC-004.
///
/// Invalidated by [BiometricsController] after every write, the way
/// [passcodeEnabledProvider] is.
final biometricsEnabledProvider = FutureProvider<bool>((ref) async {
  final isEnabled = ref.watch(isBiometricsEnabledProvider);
  final result = await isEnabled(const NoParams());
  return result.match(Future<bool>.error, Future<bool>.value);
});

/// Whether the device has a usable biometric sensor. NFR-SEC-004.
///
/// Read once for the settings row: a fingerprint enrolled while the
/// settings screen happens to be open is not a case worth watching for.
final biometricsAvailableProvider = FutureProvider<bool>((ref) async {
  final isAvailable = ref.watch(isBiometricsAvailableProvider);
  final result = await isAvailable(const NoParams());
  return result.match(Future<bool>.error, Future<bool>.value);
});

/// Turning biometric unlock on or off from Settings. NFR-SEC-004.
class BiometricsController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Turns biometric unlock on. [reason] is shown on the OS prompt. Returns
  /// the failure, if any, the same shape as [PasscodeController.set] — null
  /// covers both success and a declined prompt, since neither is an error
  /// the settings screen need show; the toggle's own state says which.
  Future<Failure?> enable(String reason) async {
    state = const AsyncValue<void>.loading();
    final result = await ref.read(enableBiometricsProvider)(reason);
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return failure;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        ref.invalidate(biometricsEnabledProvider);
        return null;
      },
    );
  }

  /// Turns biometric unlock off.
  Future<Failure?> disable() async {
    state = const AsyncValue<void>.loading();
    final result = await ref.read(disableBiometricsProvider)(const NoParams());
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return failure;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        ref.invalidate(biometricsEnabledProvider);
        return null;
      },
    );
  }
}

/// Controller for the biometrics row on the settings screen.
final biometricsControllerProvider =
    AutoDisposeAsyncNotifierProvider<BiometricsController, void>(
      BiometricsController.new,
    );
