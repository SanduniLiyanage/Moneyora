@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/features/auth/domain/entities/lockout_state.dart';
import 'package:moneyora/features/auth/domain/repositories/auth_repository.dart';
import 'package:moneyora/features/auth/domain/repositories/biometric_gateway.dart';
import 'package:moneyora/features/auth/presentation/pages/passcode_flow_page.dart';
import 'package:moneyora/features/auth/presentation/widgets/security_settings_section.dart';
import 'package:moneyora/injection.dart';

/// The Security rows and the set / change / remove flows, end to end.
///
/// The section is pumped on its own scaffold under a real `GoRouter` with
/// the passcode route, rather than inside `SettingsPage`, so the test needs
/// no settings fakes; that the settings screen draws the slot it is given
/// is `settings_page_test.dart`'s. The repository is a fake that holds the
/// PIN in the clear; the use cases, the controllers and the pages are real.
void main() {
  late _FakeRepository repository;
  late _FakeGateway gateway;
  late DateTime now;

  setUp(() {
    repository = _FakeRepository();
    gateway = _FakeGateway();
    now = DateTime(2026, 9, 21, 9);
  });

  Widget boot() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      biometricGatewayProvider.overrideWithValue(gateway),
      clockProvider.overrideWithValue(() => now),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: SingleChildScrollView(child: SecuritySettingsSection()),
            ),
          ),
          GoRoute(
            path: Routes.passcode,
            builder: (context, state) => PasscodeFlowPage(
              flow: switch (state.extra) {
                final PasscodeFlow flow => flow,
                _ => PasscodeFlow.set,
              },
            ),
          ),
        ],
      ),
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

  Future<void> tapRow(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  group('the rows', () {
    testWidgets('offer to set a passcode while there is none', (tester) async {
      await open(tester);

      expect(find.text('Set a passcode'), findsOneWidget);
      expect(find.text('Change passcode'), findsNothing);
      expect(find.text('Remove passcode'), findsNothing);
    });

    testWidgets('offer change and remove once there is one', (tester) async {
      repository.pin = '1234';
      await open(tester);

      expect(find.text('Set a passcode'), findsNothing);
      expect(find.textContaining('On. Asked for'), findsOneWidget);
      expect(find.text('Change passcode'), findsOneWidget);
      expect(find.text('Remove passcode'), findsOneWidget);
    });

    testWidgets('show a store that cannot be read in its own words', (
      tester,
    ) async {
      repository.failWith = const CacheFailure('keychain unavailable');
      await open(tester);

      expect(find.text('keychain unavailable'), findsOneWidget);
      expect(find.text('Set a passcode'), findsNothing);
    });
  });

  group('setting', () {
    testWidgets('asks twice, stores it, says so, and the rows follow', (
      tester,
    ) async {
      await open(tester);
      await tapRow(tester, 'Set a passcode');

      expect(find.text('Choose a PIN of 4 to 6 digits'), findsOneWidget);
      await enter(tester, '2580');
      expect(find.text('Enter it again'), findsOneWidget);
      await enter(tester, '2580');

      expect(repository.pin, '2580');
      expect(find.text('Passcode set.'), findsOneWidget);
      expect(find.text('Change passcode'), findsOneWidget);
      expect(find.text('Set a passcode'), findsNothing);
    });

    testWidgets('a mismatch goes back to choosing, and stores nothing', (
      tester,
    ) async {
      await open(tester);
      await tapRow(tester, 'Set a passcode');

      await enter(tester, '2580');
      await enter(tester, '2581');

      expect(
        find.text('The PINs did not match. Choose it again.'),
        findsOneWidget,
      );
      expect(find.text('Choose a PIN of 4 to 6 digits'), findsOneWidget);
      expect(repository.pin, isNull);

      // And the second try is a fresh pair.
      await enter(tester, '135790');
      await enter(tester, '135790');
      expect(repository.pin, '135790');
    });

    testWidgets('leaving stores nothing', (tester) async {
      await open(tester);
      await tapRow(tester, 'Set a passcode');
      await enter(tester, '2580');

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(repository.pin, isNull);
      expect(find.text('Set a passcode'), findsOneWidget);
    });
  });

  group('changing', () {
    setUp(() => repository.pin = '1234');

    testWidgets('proves the current PIN, then asks twice', (tester) async {
      await open(tester);
      await tapRow(tester, 'Change passcode');

      expect(find.text('Enter your current PIN'), findsOneWidget);
      await enter(tester, '1234');
      expect(find.text('Choose a PIN of 4 to 6 digits'), findsOneWidget);
      await enter(tester, '9876');
      expect(find.text('Enter it again'), findsOneWidget);
      await enter(tester, '9876');

      expect(repository.pin, '9876');
      expect(find.text('Passcode changed.'), findsOneWidget);
    });

    testWidgets('a wrong current PIN is counted and sent back to the start', (
      tester,
    ) async {
      await open(tester);
      await tapRow(tester, 'Change passcode');

      await enter(tester, '0000');
      await enter(tester, '9876');
      await enter(tester, '9876');

      expect(find.text('Wrong PIN. 4 attempts left.'), findsOneWidget);
      expect(find.text('Enter your current PIN'), findsOneWidget);
      expect(repository.pin, '1234');
      expect(repository.lockout, const LockoutState(failedAttempts: 1));
    });

    testWidgets('refuses the same PIN again, in the use case\'s words', (
      tester,
    ) async {
      await open(tester);
      await tapRow(tester, 'Change passcode');

      await enter(tester, '1234');
      await enter(tester, '1234');

      expect(
        find.text('Choose a PIN different from the current one.'),
        findsOneWidget,
      );
      expect(find.text('Choose a PIN of 4 to 6 digits'), findsOneWidget);
      expect(repository.pin, '1234');
    });

    testWidgets('a lockout reached here locks the pad here too', (
      tester,
    ) async {
      repository.lockout = const LockoutState(failedAttempts: 4);
      await open(tester);
      await tapRow(tester, 'Change passcode');

      await enter(tester, '0000');
      await enter(tester, '9876');
      await enter(tester, '9876');

      expect(
        find.text('Too many attempts. Try again in 30 s.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '1'))
            .onPressed,
        isNull,
      );
    });
  });

  group('removing', () {
    setUp(() => repository.pin = '1234');

    testWidgets('proves the PIN, clears it, and the rows follow', (
      tester,
    ) async {
      await open(tester);
      await tapRow(tester, 'Remove passcode');

      expect(find.text('Enter your current PIN'), findsOneWidget);
      await enter(tester, '1234');

      expect(repository.pin, isNull);
      expect(find.text('Passcode removed.'), findsOneWidget);
      expect(find.text('Set a passcode'), findsOneWidget);
    });

    testWidgets('a wrong PIN keeps it', (tester) async {
      await open(tester);
      await tapRow(tester, 'Remove passcode');

      await enter(tester, '0000');

      expect(find.text('Wrong PIN. 4 attempts left.'), findsOneWidget);
      expect(repository.pin, '1234');
    });
  });

  group('biometrics', () {
    testWidgets('no row while there is no passcode, even if available', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Biometric unlock'), findsNothing);
    });

    testWidgets('no row when the device has no usable sensor', (tester) async {
      repository.pin = '1234';
      gateway.available = false;
      await open(tester);

      expect(find.text('Biometric unlock'), findsNothing);
    });

    testWidgets('a row, off, once a passcode exists and the sensor agrees', (
      tester,
    ) async {
      repository.pin = '1234';
      await open(tester);

      expect(find.text('Biometric unlock'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    });

    testWidgets('turning it on prompts once, and the switch follows', (
      tester,
    ) async {
      repository.pin = '1234';
      gateway.authenticateResult = true;
      await open(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(gateway.authenticateCalls, [
        'Confirm it is you to turn on biometric unlock.',
      ]);
      expect(repository.biometricsEnabled, isTrue);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    });

    testWidgets('a declined prompt leaves the switch off', (tester) async {
      repository.pin = '1234';
      gateway.authenticateResult = false;
      await open(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(repository.biometricsEnabled, isFalse);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    });

    testWidgets('turning it off needs no prompt', (tester) async {
      repository
        ..pin = '1234'
        ..biometricsEnabled = true;
      await open(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(gateway.authenticateCalls, isEmpty);
      expect(repository.biometricsEnabled, isFalse);
    });
  });
}

class _FakeRepository implements AuthRepository {
  String? pin;
  LockoutState lockout = LockoutState.none;
  Failure? failWith;
  bool biometricsEnabled = false;

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
    return const Right(unit);
  }

  @override
  Future<Either<Failure, bool>> isBiometricsEnabled() async {
    if (failWith case final failure?) return Left(failure);
    return Right(biometricsEnabled);
  }

  @override
  Future<Either<Failure, Unit>> setBiometricsEnabled({
    required bool enabled,
  }) async {
    if (failWith case final failure?) return Left(failure);
    biometricsEnabled = enabled;
    return const Right(unit);
  }
}

/// The biometric sensor, faked. Every prompt is recorded so a test can
/// prove the toggle did or did not ask.
class _FakeGateway implements BiometricGateway {
  bool available = true;
  bool authenticateResult = false;
  final List<String> authenticateCalls = [];

  @override
  Future<Either<Failure, bool>> isAvailable() async => Right(available);

  @override
  Future<Either<Failure, bool>> authenticate(String reason) async {
    authenticateCalls.add(reason);
    return Right(authenticateResult);
  }
}
