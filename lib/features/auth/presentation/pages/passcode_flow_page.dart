import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../injection.dart';
import '../../domain/entities/lockout_state.dart';
import '../../domain/entities/passcode_format.dart';
import '../../domain/entities/pin_verdict.dart';
import '../../domain/usecases/change_passcode.dart';
import '../providers/auth_providers.dart';
import '../widgets/lockout_message.dart';
import '../widgets/pin_pad.dart';

/// Which of the three things the flow page is doing.
enum PasscodeFlow {
  /// Turning the passcode on: choose, confirm.
  set,

  /// Replacing it: prove the current one, choose, confirm.
  change,

  /// Turning it off: prove the current one.
  remove,
}

/// Setting, changing or removing the passcode, one PIN at a time.
/// FR-SET-005.
///
/// One page for the three flows because they are the same steps in
/// different orders: *prove the current PIN*, *choose a new one*, *enter it
/// again*. The pad is the lock screen's, so a PIN is typed the same way
/// everywhere; the sentences are the use cases' and the controller's, so
/// nothing this page says is a rule it invented.
///
/// Every PIN is collected first and the use case runs once, at the end. A
/// wrong current PIN therefore comes back after the new one has been typed
/// twice — the trade for keeping the "current PIN required" rule inside
/// `ChangePasscode` and `RemovePasscode`, where an unlocked phone in the
/// wrong hands cannot get round it, rather than in a screen that could be
/// skipped. It is counted against the lockout like any other wrong PIN.
///
/// Pops with a sentence for the settings screen to show on success, and
/// with nothing on cancel.
class PasscodeFlowPage extends ConsumerStatefulWidget {
  /// Creates the page for [flow].
  const PasscodeFlowPage({required this.flow, super.key});

  /// What the page is doing.
  final PasscodeFlow flow;

  @override
  ConsumerState<PasscodeFlowPage> createState() => _PasscodeFlowPageState();
}

enum _Step { current, choose, confirm }

class _PasscodeFlowPageState extends ConsumerState<PasscodeFlowPage> {
  late _Step _step = _firstStep;
  String _entered = '';
  String? _current;
  String? _chosen;
  String? _message;
  LockoutState _lockout = LockoutState.none;
  bool _busy = false;

  _Step get _firstStep => switch (widget.flow) {
    PasscodeFlow.set => _Step.choose,
    PasscodeFlow.change || PasscodeFlow.remove => _Step.current,
  };

  String get _title => switch (widget.flow) {
    PasscodeFlow.set => 'Set a passcode',
    PasscodeFlow.change => 'Change passcode',
    PasscodeFlow.remove => 'Remove passcode',
  };

  String get _prompt => switch (_step) {
    _Step.current => 'Enter your current PIN',
    _Step.choose => 'Choose a PIN of 4 to 6 digits',
    _Step.confirm => 'Enter it again',
  };

  /// What the settings screen says once this page has done its job.
  String get _done => switch (widget.flow) {
    PasscodeFlow.set => 'Passcode set.',
    PasscodeFlow.change => 'Passcode changed.',
    PasscodeFlow.remove => 'Passcode removed.',
  };

  void _goTo(_Step step, {String? message}) => setState(() {
    _step = step;
    _entered = '';
    _message = message;
  });

  Future<void> _submit() async {
    final pin = _entered;
    switch (_step) {
      case _Step.current:
        _current = pin;
        if (widget.flow == PasscodeFlow.remove) return _run();
        _goTo(_Step.choose);
      case _Step.choose:
        // The use case's own refusals, before asking for it twice.
        final refusal = widget.flow == PasscodeFlow.change
            ? ChangePasscode.validate(
                ChangePasscodeParams(current: _current!, next: pin),
              )
            : PasscodeFormat.validate(pin);
        if (refusal != null) {
          return _goTo(_Step.choose, message: refusal.message);
        }
        _chosen = pin;
        _goTo(_Step.confirm);
      case _Step.confirm:
        if (pin != _chosen) {
          return _goTo(
            _Step.choose,
            message: 'The PINs did not match. Choose it again.',
          );
        }
        return _run();
    }
  }

  /// Runs the flow's use case, and reads its answer.
  Future<void> _run() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final controller = ref.read(passcodeControllerProvider.notifier);
    final Either<Failure, PinVerdict> result = switch (widget.flow) {
      PasscodeFlow.set => switch (await controller.set(_chosen!)) {
        final Failure failure => Left(failure),
        null => const Right(PinAccepted()),
      },
      PasscodeFlow.change => await controller.change(
        current: _current!,
        next: _chosen!,
      ),
      PasscodeFlow.remove => await controller.remove(_current!),
    };
    if (!mounted) return;
    setState(() => _busy = false);

    result.match(
      (failure) => _goTo(_firstStep, message: failure.message),
      (verdict) => switch (verdict) {
        PinAccepted() => Navigator.of(context).pop(_done),
        PinRejected(:final lockout) ||
        PinLockedOut(:final lockout) => _refused(lockout),
      },
    );
  }

  /// A wrong current PIN: back to the start, with the gate's own sentence.
  void _refused(LockoutState lockout) {
    setState(() {
      _lockout = lockout;
      _step = _Step.current;
      _entered = '';
      _current = null;
      _chosen = null;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = _lockout.isLockedAt(ref.read(clockProvider)());

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _prompt,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (_message case final String message)
                  SizedBox(
                    height: 40,
                    child: Center(
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  )
                else
                  LockoutMessage(
                    lockout: _lockout,
                    onExpired: () => setState(() {}),
                  ),
                const SizedBox(height: 8),
                PinPad(
                  entered: _entered,
                  enabled: !_busy && !locked,
                  onChanged: (value) => setState(() => _entered = value),
                  onSubmit: _submit,
                ),
                SizedBox(
                  height: 24,
                  child: _busy
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
