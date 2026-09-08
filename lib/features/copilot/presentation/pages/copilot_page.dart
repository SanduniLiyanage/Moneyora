import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/copilot_answer.dart';
import '../providers/copilot_providers.dart';

/// The Copilot screen: ask a question, see the answer and how it was reached.
///
/// Refs: FR-COP-001 (input), FR-COP-002 (loading, non-blocking),
/// FR-COP-003 (the tool trace), FR-COP-014 (the offline message).
///
/// ## Why the trace is on the screen and not behind a toggle
///
/// An answer about someone's own money is worth little if they cannot see
/// where the number came from. A model can be confidently wrong, and the
/// defence offered here is not a promise that it is right — it is showing
/// which of their own figures it read, so they can check.
class CopilotPage extends ConsumerStatefulWidget {
  /// Creates the Copilot screen.
  const CopilotPage({super.key});

  @override
  ConsumerState<CopilotPage> createState() => _CopilotPageState();
}

class _CopilotPageState extends ConsumerState<CopilotPage> {
  final TextEditingController _question = TextEditingController();

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  void _ask() {
    FocusScope.of(context).unfocus();
    unawaited(ref.read(copilotProvider.notifier).ask(_question.text));
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = ref.watch(copilotHasKeyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ask Moneyora')),
      body: SafeArea(
        child: switch (hasKey) {
          AsyncData(value: false) => const _ConnectTheAssistant(),
          AsyncData(value: true) => _AskAndAnswer(
            controller: _question,
            onAsk: _ask,
          ),
          AsyncError() => const _ConnectTheAssistant(),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

/// The question box, the answer, and everything in between.
class _AskAndAnswer extends ConsumerWidget {
  const _AskAndAnswer({required this.controller, required this.onAsk});

  final TextEditingController controller;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(copilotProvider);
    final busy = state.isLoading;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: controller,
                enabled: !busy,
                maxLines: null,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'How much did I spend on food in August?',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onAsk(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  // Disabled while a question is in flight: a second request
                  // would spend another round trip to overwrite the first.
                  onPressed: busy ? null : onAsk,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(busy ? 'Thinking…' : 'Ask'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (state) {
            AsyncLoading() => const _Thinking(),
            AsyncError(:final error) => _Problem(
              message: copilotErrorMessage(error),
            ),
            AsyncData(value: final answer?) => _Answer(answer: answer),
            _ => const _Suggestions(),
          },
        ),
      ],
    );
  }
}

/// Shown before the first question.
///
/// Examples rather than an empty box: a person meeting an open text field has
/// no idea what this thing can do, and "ask me anything" is the least helpful
/// instruction an interface can give.
class _Suggestions extends StatelessWidget {
  const _Suggestions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Text('Try asking', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final example in const [
          'How much did I spend on food in August?',
          'What were my three biggest categories last month?',
          'Did I spend more on transport this month than last?',
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('· '),
                Expanded(
                  child: Text(example, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'Your transactions stay on this phone. Only the totals needed to '
          'answer a question are sent, never individual records.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Reading your figures…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// The answer, with the tools it was built from.
class _Answer extends StatelessWidget {
  const _Answer({required this.answer});

  final CopilotAnswer answer;

  /// Turns a tool name into something a person can read.
  ///
  /// The model sees `get_spending_by_category`; the user should not.
  static String _describe(String toolName) => switch (toolName) {
    'get_spending_by_category' => 'your spending by category',
    'get_income_for_period' => 'your income for the period',
    'compare_periods' => 'a comparison between two periods',
    _ => toolName.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SelectableText(answer.text, style: theme.textTheme.bodyLarge),
        if (answer.trace.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('I looked at', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final call in answer.trace)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _describe(call.toolName),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Offline, quota spent, or the service down — all of them recoverable.
///
/// Deliberately not an error page. The Copilot failing means one optional
/// feature is unavailable, and the screen says so in a way that does not
/// suggest the app itself is broken (NFR-REL-004).
class _Problem extends StatelessWidget {
  const _Problem({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Everything else in Moneyora works without a connection.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown until an API key exists.
///
/// The key is entered here rather than in Settings because it belongs to this
/// feature alone: without one the Copilot cannot run, and with one nothing
/// else in the app behaves differently. Removing the feature would otherwise
/// leave a stray field in a screen that has nothing to do with it.
class _ConnectTheAssistant extends ConsumerStatefulWidget {
  const _ConnectTheAssistant();

  @override
  ConsumerState<_ConnectTheAssistant> createState() =>
      _ConnectTheAssistantState();
}

class _ConnectTheAssistantState extends ConsumerState<_ConnectTheAssistant> {
  final TextEditingController _key = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_key.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await saveCopilotApiKey(ref, _key.text);
    if (mounted) {
      _key.clear();
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.auto_awesome_outlined, size: 40, color: colors.transfer),
        const SizedBox(height: 16),
        Text('Connect the assistant', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'The Copilot reads your figures on this phone and asks a language '
          'model to explain them. It needs a free Google AI Studio key, which '
          'is stored in this device keychain and never leaves it.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _key,
          enabled: !_saving,
          // Obscured: the field holds a credential, and a key read off a
          // shoulder or a screen recording is a key that has to be replaced.
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'API key',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save key'),
        ),
        const SizedBox(height: 24),
        Text(
          'Until then, every other part of Moneyora works exactly as it does '
          'now — the Copilot is the only feature that uses a connection.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
