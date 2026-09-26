import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../injection.dart';
import '../../domain/usecases/create_backup.dart';
import '../providers/backup_providers.dart';

/// The rows under Settings › Data for backup and restore. FR-SET-009,
/// FR-BAK-001, FR-BAK-005.
///
/// Handed to `SettingsPage` by the router, as the Security rows are, because
/// the settings feature may not import this one (rule 4).
class BackupSettingsSection extends ConsumerWidget {
  /// Creates the section.
  const BackupSettingsSection({super.key});

  Future<void> _backUp(BuildContext context, WidgetRef ref) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(confirm: true),
    );
    if (password == null || !context.mounted) return;

    final outcome = await ref
        .read(backupControllerProvider.notifier)
        .backUp(password);
    if (context.mounted) _say(context, outcome.message);
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final bytes = await ref.read(backupFileGatewayProvider).pick();
    if (bytes == null || !context.mounted) return;

    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything on this phone?'),
        content: const Text(
          'Every transaction, account, plan and setting here is replaced by '
          "the backup's. This cannot be undone, so back this phone up first "
          'if you might want it back. Your passcode stays as it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (replace != true || !context.mounted) return;

    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(confirm: false),
    );
    if (password == null || !context.mounted) return;

    final outcome = await ref
        .read(backupControllerProvider.notifier)
        .restore(bytes, password);
    if (context.mounted) _say(context, outcome.message);
  }

  static void _say(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(backupControllerProvider).isLoading;

    Widget leading(IconData icon) => busy
        ? const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          enabled: !busy,
          leading: leading(Icons.backup_outlined),
          title: const Text('Back up now'),
          subtitle: const Text(
            'An encrypted file, sealed with a password, that any phone with '
            'Moneyora can restore. Save it off this phone.',
          ),
          onTap: busy ? null : () => _backUp(context, ref),
        ),
        ListTile(
          enabled: !busy,
          leading: leading(Icons.settings_backup_restore_outlined),
          title: const Text('Restore from a backup'),
          subtitle: const Text(
            "Replaces everything on this phone with a backup's contents.",
          ),
          onTap: busy ? null : () => _restore(context, ref),
        ),
      ],
    );
  }
}

/// Asks for the backup's password — twice, when making one, because a
/// mistyped password on a new backup makes it unopenable and nothing can
/// recover it (E-38).
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.confirm});

  /// Whether this is a new backup's password, checked and asked twice.
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  String? get _problem {
    if (!widget.confirm) return null;
    if (CreateBackup.validate(_password.text) case final failure?) {
      return failure.message;
    }
    if (_again.text != _password.text) {
      return 'The two passwords are different.';
    }
    return null;
  }

  void _done() {
    setState(() => _submitted = true);
    if (_problem != null || _password.text.isEmpty) return;
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final error = _submitted ? _problem : null;
    return AlertDialog(
      title: Text(widget.confirm ? 'Protect the backup' : 'Open the backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: widget.confirm
                  ? 'Nothing can open the backup without it, and it cannot '
                        'be recovered.'
                  : null,
              helperMaxLines: 3,
              errorText: widget.confirm ? null : error,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.confirm)
            TextField(
              controller: _again,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'The same password again',
                errorText: error,
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _done(),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _done,
          child: Text(widget.confirm ? 'Back up' : 'Restore'),
        ),
      ],
    );
  }
}
