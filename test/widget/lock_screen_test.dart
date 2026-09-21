@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/auth/domain/entities/lockout_state.dart';
import 'package:moneyora/features/auth/domain/repositories/auth_repository.dart';
import 'package:moneyora/features/auth/presentation/providers/auth_providers.dart';
import 'package:moneyora/features/auth/presentation/widgets/auth_gate.dart';
import 'package:moneyora/injection.dart';

/// The gate and the lock screen, driven the way a person drives them.
///
/// The repository is a fake that holds the PIN in the clear; everything
/// above it is real — the use cases, the lockout policy, the controllers,
/// the gate and the screen. The clock is the test's, so a thirty-second
/// lockout is served by moving it. The harness is `MaterialApp.router` over
/// a real `GoRouter`, as `app.dart` is, because whether the back button
/// reaches the gate before the router depends on that arrangement.
void main() {
  late _FakeRepository repository;
  late DateTime now;

  final t0 = DateTime(2026, 9, 21, 9);

  setUp(() {
    repository = _FakeRepository();
    now = t0;
  });

  Widget boot() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      clockProvider.overrideWithValue(() => now),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => context.push('/second'),
                  child: const Text('Home'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/second',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Second'))),
          ),
        ],
      ),
      builder: (context, child) =>
          AuthGate(child: child ?? const SizedBox.shrink()),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();
  }

  /// Types [pin] on the pad and presses the tick.
  Future<void> enter(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.widgetWithText(TextButton, digit));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
  }

  bool keyEnabled(WidgetTester tester, String digit) =>
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, digit))
          .onPressed !=
      null;

  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pumpAndSettle();
  }

  group('with no passcode', () {
    testWidgets('the app is simply shown', (tester) async {
      await open(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Enter your PIN'), findsNothing);
    });

    testWidgets('going to the background and back changes nothing', (
      tester,
    ) async {
      await open(tester);

      await lifecycle(tester, AppLifecycleState.paused);
      now = now.add(const Duration(hours: 1));
      await lifecycle(tester, AppLifecycleState.resumed);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Enter your PIN'), findsNothing);
    });

    testWidgets('a keychain that cannot be read fails open', (tester) async {
      // The database key is in the same keychain and will have failed too;
      // the home screen's own error is what the user should see, not a
      // lock no PIN can pass.
      repository.failWith = const CacheFailure('keychain unavailable');
      await open(tester);

      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('with a passcode', () {
    setUp(() => repository.pin = '1234');

    testWidgets('the lock screen is in front, and the app is kept behind it', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Enter your PIN'), findsOneWidget);
      // Not visible — and not gone: the Navigator is offstage, not removed.
      expect(find.text('Home'), findsNothing);
      expect(find.text('Home', skipOffstage: false), findsOneWidget);
    });

    testWidgets('the right PIN opens it', (tester) async {
      await open(tester);

      await enter(tester, '1234');

      expect(find.text('Enter your PIN'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      // The PIN never reached the lockout store: a clean slate stays clean.
      expect(repository.lockoutWrites, isEmpty);
    });

    testWidgets('a wrong PIN says so, in the gate\'s words, and clears', (
      tester,
    ) async {
      await open(tester);

      await enter(tester, '9999');

      expect(find.text('Wrong PIN. 4 attempts left.'), findsOneWidget);
      expect(find.text('Enter your PIN'), findsOneWidget);
      // The row was cleared: the next digit is the first of a new attempt.
      expect(
        find.bySemanticsLabel(RegExp(r'PIN, 0 of up to 6 digits')),
        findsOneWidget,
      );
    });

    testWidgets('the tick is off until there are four digits', (tester) async {
      await open(tester);

      for (final digit in ['1', '2', '3']) {
        await tester.tap(find.widgetWithText(TextButton, digit));
        await tester.pump();
      }
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check))
            .onPressed,
        isNull,
      );

      await tester.tap(find.widgetWithText(TextButton, '4'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('five wrong PINs lock the pad, the countdown runs, and the '
        'pad comes back when it ends', (tester) async {
      await open(tester);

      for (var i = 0; i < 5; i++) {
        await enter(tester, '0000');
      }

      expect(
        find.text('Too many attempts. Try again in 30 s.'),
        findsOneWidget,
      );
      expect(keyEnabled(tester, '1'), isFalse);

      // The clock moves and the ticker fires once a second.
      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('Too many attempts. Try again in 20 s.'),
        findsOneWidget,
      );
      expect(keyEnabled(tester, '1'), isFalse);

      now = now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Too many attempts'), findsNothing);
      expect(keyEnabled(tester, '1'), isTrue);

      // And the right PIN now goes through.
      await enter(tester, '1234');
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('a lockout that was running when the app closed is still '
        'running when it opens', (tester) async {
      repository.lockout = LockoutState(
        failedAttempts: 5,
        lockedUntil: t0.add(const Duration(minutes: 1, seconds: 5)),
      );
      await open(tester);

      expect(
        find.text('Too many attempts. Try again in 1:05.'),
        findsOneWidget,
      );
      expect(keyEnabled(tester, '1'), isFalse);
    });

    testWidgets('re-locks after a long time in the background, not a short '
        'one', (tester) async {
      await open(tester);
      await enter(tester, '1234');
      expect(find.text('Home'), findsOneWidget);

      // Gone ten seconds: the app locked while away (the switcher's
      // snapshot is the lock screen) and opens itself on return. No frame
      // is drawn while paused — the binding stops them, as a device does —
      // so the lock while away is read from the controller, not the screen.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AuthGate)),
      );
      await lifecycle(tester, AppLifecycleState.paused);
      expect(container.read(appLockProvider).valueOrNull, isTrue);
      now = now.add(const Duration(seconds: 10));
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Enter your PIN'), findsNothing);

      // Gone thirty: it stays locked.
      await lifecycle(tester, AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 30));
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('a lock the user was already looking at survives a short '
        'absence', (tester) async {
      // Only a pause-lock is undone on return; the launch lock is not,
      // or leaving and coming back inside the grace would be a way past it.
      await open(tester);
      expect(find.text('Enter your PIN'), findsOneWidget);

      await lifecycle(tester, AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 5));
      await lifecycle(tester, AppLifecycleState.resumed);

      expect(find.text('Enter your PIN'), findsOneWidget);
    });

    testWidgets('the back button is swallowed while locked, and the stack '
        'behind the gate is untouched', (tester) async {
      await open(tester);
      await enter(tester, '1234');
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);

      await lifecycle(tester, AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 1));
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(find.text('Enter your PIN'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.text('Second', skipOffstage: false), findsOneWidget);

      // And once through, the user is where they left off.
      await enter(tester, '1234');
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('a store that fails mid-attempt is shown in its own words', (
      tester,
    ) async {
      await open(tester);
      repository.failWith = const CacheFailure('keychain unavailable');

      await enter(tester, '1234');

      expect(find.text('keychain unavailable'), findsOneWidget);
      expect(find.text('Enter your PIN'), findsOneWidget);
    });
  });
}

class _FakeRepository implements AuthRepository {
  String? pin;
  LockoutState lockout = LockoutState.none;
  Failure? failWith;
  final List<LockoutState> lockoutWrites = [];

  @override
  Future<Either<Failure, bool>> hasPasscode() async {
    if (failWith case final failure?) return Left(failure);
    return Right(pin != null);
  }

  @override
  Future<Either<Failure, Unit>> setPasscode(String pin) async {
    if (failWith case final failure?) return Left(failure);
    this.pin = pin;
    lockout = LockoutState.none;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> clearPasscode() async {
    if (failWith case final failure?) return Left(failure);
    pin = null;
    lockout = LockoutState.none;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, bool>> matchesPasscode(String pin) async {
    if (failWith case final failure?) return Left(failure);
    return Right(this.pin != null && this.pin == pin);
  }

  @override
  Future<Either<Failure, LockoutState>> getLockout() async {
    if (failWith case final failure?) return Left(failure);
    return Right(lockout);
  }

  @override
  Future<Either<Failure, Unit>> saveLockout(LockoutState state) async {
    if (failWith case final failure?) return Left(failure);
    lockout = state;
    lockoutWrites.add(state);
    return const Right(unit);
  }
}
