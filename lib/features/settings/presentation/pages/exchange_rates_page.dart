import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/exchange_rate.dart';
import '../../domain/usecases/remove_exchange_rate.dart';
import '../../domain/usecases/set_exchange_rate.dart';
import '../providers/settings_providers.dart';

/// The exchange-rate table the user keeps. FR-SET-003, FR-ACC-005, E-34.
///
/// "User-configurable" in the SRS means this screen: one row per pair, the
/// rate a bank actually applied written down from the statement, replaced
/// when a newer one is known. There is no fetch, so nothing here is ever
/// stale in a way the user did not choose.
///
/// Every rule enforced here is [SetExchangeRate.validate], **called** rather
/// than restated: the form runs it as the user types so a problem appears
/// next to the field, and the use case runs it again on save.
class ExchangeRatesPage extends ConsumerWidget {
  /// Creates the screen.
  const ExchangeRatesPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    ExchangeRate? initial,
  }) async {
    final rate = await showDialog<ExchangeRate>(
      context: context,
      builder: (context) => _RateDialog(initial: initial),
    );
    if (rate == null || !context.mounted) return;

    final failure = await ref
        .read(exchangeRateControllerProvider.notifier)
        .set(rate);
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }

  /// Forgets a rate, after asking. Safe by construction — E-34 — but a row
  /// that vanishes on one tap is still a surprise.
  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ExchangeRate rate,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${rate.fromCurrency} → ${rate.toCurrency}?'),
        content: Text(
          'Accounts in ${rate.fromCurrency} will be shown in their own '
          'currency and left out of your total until a rate is entered '
          'again. Nothing already recorded changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final failure = await ref
        .read(exchangeRateControllerProvider.notifier)
        .remove(
          CurrencyPair(
            fromCurrency: rate.fromCurrency,
            toCurrency: rate.toCurrency,
          ),
        );
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rates = ref.watch(exchangeRatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Exchange rates')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref),
        tooltip: 'Add rate',
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: switch (rates) {
          AsyncData(value: final list) when list.isEmpty => _Empty(
            theme: theme,
          ),
          AsyncData(value: final list) => ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final rate = list[index];
              return ListTile(
                title: Text('${rate.fromCurrency} → ${rate.toCurrency}'),
                subtitle: Text(
                  '1 ${rate.fromCurrency} = '
                  '${formatRateMicros(rate.rateMicros)} ${rate.toCurrency}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: () => _remove(context, ref, rate),
                ),
                onTap: () => _edit(context, ref, initial: rate),
              );
            },
          ),
          AsyncError(:final Failure error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(error.message, textAlign: TextAlign.center),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

/// E-22's first-time empty state: what will appear here, and how.
class _Empty extends StatelessWidget {
  const _Empty({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No exchange rates yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Add the rate your bank uses for each currency you hold, and '
            'Moneyora will count those accounts in your total balance.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Entering or editing one rate. Returns the rate, or null on cancel.
class _RateDialog extends StatefulWidget {
  const _RateDialog({this.initial});

  final ExchangeRate? initial;

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late final TextEditingController _from;
  late final TextEditingController _to;
  late final TextEditingController _rate;
  bool _submitted = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _from = TextEditingController(text: initial?.fromCurrency ?? '');
    _to = TextEditingController(text: initial?.toCurrency ?? '');
    _rate = TextEditingController(
      text: initial == null ? '' : formatRateMicros(initial.rateMicros),
    );
    for (final controller in [_from, _to, _rate]) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _rate.dispose();
    super.dispose();
  }

  ExchangeRate _build() => ExchangeRate(
    fromCurrency: _from.text,
    toCurrency: _to.text,
    rateMicros: parseRateMicros(_rate.text) ?? 0,
    updatedAt: DateTime.now(),
  );

  ValidationFailure? get _problem => SetExchangeRate.validate(_build());

  String? _errorFor(String field) {
    if (!_submitted) return null;
    final problem = _problem;
    return problem != null && problem.field == field ? problem.message : null;
  }

  void _save() {
    setState(() => _submitted = true);
    if (_problem != null) return;
    Navigator.of(context).pop(_build());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_isEditing ? 'Edit rate' : 'Add rate'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _from,
                // The pair is the row's identity; editing it would be a
                // different rate, so on an edit only the number changes.
                enabled: !_isEditing,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.characters,
                maxLength: 3,
                decoration: InputDecoration(
                  labelText: 'From',
                  hintText: 'USD',
                  counterText: '',
                  errorText: _errorFor('fromCurrency'),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 20, 8, 0),
              child: Icon(Icons.arrow_forward, size: 18),
            ),
            Expanded(
              child: TextField(
                controller: _to,
                enabled: !_isEditing,
                textCapitalization: TextCapitalization.characters,
                maxLength: 3,
                decoration: InputDecoration(
                  labelText: 'To',
                  hintText: 'LKR',
                  counterText: '',
                  errorText: _errorFor('toCurrency'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _rate,
          autofocus: _isEditing,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Rate',
            hintText: '300.25',
            helperText:
                'How much of the second currency one unit of the '
                'first is worth.',
            helperMaxLines: 2,
            errorText: _errorFor('rate'),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
