import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/router/app_router.dart';
import '../pages/passcode_flow_page.dart';
import '../providers/auth_providers.dart';

/// The rows under Settings › Security. FR-SET-005.
///
/// Built here and handed to `SettingsPage` by the router rather than drawn
/// by the settings screen itself, because the passcode belongs to the auth
/// feature and one feature may not import another (rule 4) — the way the
/// accounts panel reaches the home screen.
///
/// Reads [passcodeEnabledProvider] for which rows to offer: *Set a passcode*
/// while there is none; *Change passcode* and *Remove passcode* once there
/// is. Each opens the flow page, which pops with a sentence to show. NFR-
/// SEC-004's biometrics row lands here with its slice.
class SecuritySettingsSection extends ConsumerWidget {
  /// Creates the section.
  const SecuritySettingsSection({super.key});

  Future<void> _open(BuildContext context, PasscodeFlow flow) async {
    final done = await context.push<String>(Routes.passcode, extra: flow);
    if (done == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(passcodeEnabledProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Security',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        switch (enabled) {
          AsyncData(value: false) => ListTile(
            leading: const Icon(Icons.lock_open_outlined),
            title: const Text('Set a passcode'),
            subtitle: const Text(
              'Ask for a 4 to 6 digit PIN when the app opens, and after it '
              'has been in the background for half a minute.',
            ),
            onTap: () => _open(context, PasscodeFlow.set),
          ),
          AsyncData(value: true) => Column(
            children: [
              const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Passcode'),
                subtitle: Text(
                  'On. Asked for when the app opens, and after it has been '
                  'in the background for half a minute.',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('Change passcode'),
                onTap: () => _open(context, PasscodeFlow.change),
              ),
              ListTile(
                leading: const Icon(Icons.no_encryption_gmailerrorred_outlined),
                title: const Text('Remove passcode'),
                onTap: () => _open(context, PasscodeFlow.remove),
              ),
            ],
          ),
          AsyncError(:final Failure error) => ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Passcode'),
            subtitle: Text(error.message),
          ),
          // Loading, or an error that is not a Failure: the row is not
          // interactive until the value it would be changing is known.
          _ => const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Passcode'),
            enabled: false,
          ),
        },
      ],
    );
  }
}
