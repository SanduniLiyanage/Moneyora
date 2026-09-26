import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/notification_settings.dart';
import '../../../../core/router/app_router.dart';
import '../../domain/entities/user_settings.dart';
import '../../domain/usecases/set_base_currency.dart';
import '../../domain/usecases/set_first_day_of_month.dart';
import '../../domain/usecases/set_plan_analysis_months.dart';
import '../../domain/usecases/set_reminder_schedule.dart';
import '../providers/settings_providers.dart';

/// The settings screen. SDD SCR-016.
///
/// Sections arrive with the requirements that fill them: the rows it draws
/// are the ones whose use cases exist. A section for a feature that is not
/// built yet would be furniture rather than information, so none is drawn
/// ahead of its slice.
///
/// *Appearance* holds FR-SET-001's theme choice. The three options are the
/// three values `users.theme` can hold, and choosing one is drawn by the app
/// root the moment it is stored — this screen writes and never sets a theme
/// itself.
///
/// *Currency* holds FR-SET-003: the base currency totals are expressed in,
/// and the rate table (its own screen). Neither converts anything by itself
/// — conversion is FR-ACC-005's, and lands beside the totals it changes.
///
/// *Calendar* holds FR-SET-004's first day of the week and of the month,
/// and FR-SET-012's lookback. The week and the month cut every analytics
/// period and every plan period; the lookback is read by the Money Plan
/// wizard, which says where to change it and does not offer to.
///
/// *Notifications* holds FR-SET-007's budget alerts, off until turned on
/// here — which is where the platform's permission is asked for, so the
/// prompt arrives with the choice it is for (E-35).
///
/// *Security* is not drawn here at all. Its rows belong to the auth feature
/// (FR-SET-005), which this screen may not import, so the router hands them
/// in as [securitySection] — the way the accounts panel reaches the home
/// screen — and this screen places them between Calendar and Data.
///
/// *Data*'s row is not a preference at all. "Recalculate account balances"
/// is E-18's reconciliation, reachable from here and from nowhere else:
/// `RecomputeAllAccountBalances` re-derives every cached balance from
/// history, which repairs drift that arrived from outside the app's own
/// write paths — a restored backup, a crash mid-write, a database edited by
/// hand. The app's own writes keep the cache exact inside the same
/// transaction as the row that moves it, so this is a repair to ask for, not
/// a task to schedule.
class SettingsPage extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsPage({super.key, this.securitySection});

  /// The Security section's rows, if supplied.
  ///
  /// Passed in by `core/router/app_router.dart` rather than constructed here,
  /// because the passcode belongs to the auth feature and a feature may not
  /// import another (rule 4 of `scripts/check_architecture.sh`).
  final Widget? securitySection;

  /// Stores [mode], and shows the failure if it could not be. FR-SET-001.
  ///
  /// Nothing to confirm and nothing to say on success: the screen changing
  /// colour is the confirmation.
  Future<void> _setTheme(
    BuildContext context,
    WidgetRef ref,
    AppThemeMode mode,
  ) async {
    final failure = await ref.read(themeControllerProvider.notifier).set(mode);
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }

  /// Asks for a three-letter code, stores it, shows the failure if any.
  /// FR-SET-003.
  Future<void> _setBaseCurrency(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => _BaseCurrencyDialog(initial: current),
    );
    if (code == null || !context.mounted) return;

    final failure = await ref
        .read(baseCurrencyControllerProvider.notifier)
        .set(code);
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }

  /// Shows a failure from any calendar or notification write. FR-SET-004,
  /// FR-SET-007, FR-SET-012.
  void _report(BuildContext context, Failure? failure) {
    if (failure == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }

  /// Asks for a whole number in a range, or null on cancel.
  Future<int?> _askNumber(
    BuildContext context, {
    required String title,
    required String label,
    required int initial,
    required ValidationFailure? Function(int) validate,
    String? help,
  }) => showDialog<int>(
    context: context,
    builder: (context) => _NumberDialog(
      title: title,
      label: label,
      initial: initial,
      validate: validate,
      help: help,
    ),
  );

  /// Asks first, then runs the sweep and reports how it went. E-18.
  ///
  /// The dialog is there because the action reads every transaction of every
  /// account, and a full-history scan started by a stray tap on a settings
  /// row is exactly the kind of work that should be confirmed. The sentences
  /// shown afterwards are the controller's: the success line here, and the
  /// use case's own failure message when it refuses.
  Future<void> _recalculate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recalculate account balances?'),
        content: const Text(
          'Every balance is worked out again from its opening balance and '
          'every transaction since. Use this after restoring a backup, or if '
          'a balance does not match its transactions. Nothing is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Recalculate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final failure = await ref
        .read(recalculateBalancesControllerProvider.notifier)
        .run();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failure?.message ?? 'Account balances recalculated.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(recalculateBalancesControllerProvider).isLoading;
    final alertsBusy = ref.watch(budgetAlertsControllerProvider).isLoading;
    final remindersBusy = ref
        .watch(recurringRemindersControllerProvider)
        .isLoading;
    final settings = ref.watch(settingsProvider);
    final theme = settings.asData?.value.theme;
    final baseCurrency = settings.asData?.value.currency;
    final calendar = settings.asData?.value;
    final rateCount = ref.watch(exchangeRatesProvider).asData?.value.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            const _SectionHeader('Appearance'),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Theme'),
              // The stored choice, or its failure's own sentence while there
              // is no choice to show. Loading shows neither: the row is not
              // interactive until the value it would be changing is known.
              subtitle: switch (settings) {
                AsyncError(:final Failure error) => Text(error.message),
                _ => null,
              },
            ),
            if (theme != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<AppThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: AppThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.phone_android_outlined),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {theme},
                  onSelectionChanged: (chosen) =>
                      _setTheme(context, ref, chosen.single),
                ),
              ),
            const _SectionHeader('Currency'),
            ListTile(
              leading: const Icon(Icons.currency_exchange_outlined),
              title: const Text('Base currency'),
              subtitle: Text(
                baseCurrency == null
                    ? 'The currency your total balance is shown in.'
                    : '$baseCurrency — the currency your total balance is '
                          'shown in.',
              ),
              enabled: baseCurrency != null,
              onTap: baseCurrency == null
                  ? null
                  : () => _setBaseCurrency(context, ref, baseCurrency),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_outlined),
              title: const Text('Exchange rates'),
              subtitle: Text(switch (rateCount) {
                null =>
                  'The rates used to count other currencies in your '
                      'total.',
                0 =>
                  'None yet. Add one to count an account held in another '
                      'currency.',
                1 => 'One rate.',
                final n => '$n rates.',
              }),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.exchangeRates),
            ),
            const _SectionHeader('Calendar'),
            const ListTile(
              leading: Icon(Icons.view_week_outlined),
              title: Text('Week starts on'),
              subtitle: Text(
                'Where a week begins in every weekly total and plan.',
              ),
            ),
            if (calendar != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: DateTime.sunday,
                      label: Text('Sunday'),
                    ),
                    ButtonSegment(
                      value: DateTime.monday,
                      label: Text('Monday'),
                    ),
                  ],
                  selected: {calendar.firstDayOfWeek},
                  onSelectionChanged: (chosen) async {
                    final failure = await ref
                        .read(calendarControllerProvider.notifier)
                        .setFirstDayOfWeek(chosen.single);
                    if (context.mounted) _report(context, failure);
                  },
                ),
              ),
            ListTile(
              leading: const Icon(Icons.calendar_view_month_outlined),
              title: const Text('Month starts on day'),
              subtitle: Text(
                calendar == null
                    ? 'Where a month begins — the 25th, if that is payday.'
                    : calendar.firstDayOfMonth == 1
                    ? 'Day 1 — the calendar month.'
                    : 'Day ${calendar.firstDayOfMonth} — a month runs from '
                          'the ${_ordinal(calendar.firstDayOfMonth)} to the '
                          'day before it.',
              ),
              enabled: calendar != null,
              onTap: calendar == null
                  ? null
                  : () async {
                      final day = await _askNumber(
                        context,
                        title: 'Month starts on day',
                        label: 'Day of the month',
                        initial: calendar.firstDayOfMonth,
                        validate: SetFirstDayOfMonth.validate,
                        help:
                            '1 to 28, so every month has it. Analytics and '
                            'plans that cover a month run from this day to the '
                            'day before it next month.',
                      );
                      if (day == null || !context.mounted) return;
                      final failure = await ref
                          .read(calendarControllerProvider.notifier)
                          .setFirstDayOfMonth(day);
                      if (context.mounted) _report(context, failure);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('Money Plan looks back'),
              subtitle: Text(
                calendar == null
                    ? 'How many months of spending a new plan learns from.'
                    : calendar.planAnalysisMonths == 1
                    ? 'One month of spending.'
                    : '${calendar.planAnalysisMonths} months of spending.',
              ),
              enabled: calendar != null,
              onTap: calendar == null
                  ? null
                  : () async {
                      final months = await _askNumber(
                        context,
                        title: 'Money Plan looks back',
                        label: 'Months',
                        initial: calendar.planAnalysisMonths,
                        validate: SetPlanAnalysisMonths.validate,
                        help:
                            '1 to 24. Seasonal patterns need a year or '
                            'more of history to show up.',
                      );
                      if (months == null || !context.mounted) return;
                      final failure = await ref
                          .read(calendarControllerProvider.notifier)
                          .setPlanAnalysisMonths(months);
                      if (context.mounted) _report(context, failure);
                    },
            ),
            if (securitySection case final Widget section) section,
            const _SectionHeader('Notifications'),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Budget alerts'),
              subtitle: const Text(
                'A notification when a category of your active plan reaches '
                '80% of its budget, and again at 100%.',
              ),
              value: calendar?.budgetAlertsEnabled ?? false,
              // Not interactive until the stored value is known, nor while a
              // change — and its permission prompt — is under way.
              onChanged: calendar == null || alertsBusy
                  ? null
                  : (enabled) async {
                      final failure = await ref
                          .read(budgetAlertsControllerProvider.notifier)
                          .set(enabled: enabled);
                      if (context.mounted) _report(context, failure);
                    },
            ),
            // FR-SET-006, E-37.
            SwitchListTile(
              secondary: const Icon(Icons.event_repeat_outlined),
              title: const Text('Recurring reminders'),
              subtitle: const Text(
                'A notification before a repeating expense or income is '
                'added.',
              ),
              value: calendar?.recurringRemindersEnabled ?? false,
              onChanged: calendar == null || remindersBusy
                  ? null
                  : (enabled) async {
                      final failure = await ref
                          .read(recurringRemindersControllerProvider.notifier)
                          .set(enabled: enabled);
                      if (context.mounted) _report(context, failure);
                    },
            ),
            if (calendar != null && calendar.recurringRemindersEnabled)
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Remind me'),
                subtitle: Text(
                  describeReminderSchedule(
                    context,
                    daysBefore: calendar.reminderDaysBefore,
                    minuteOfDay: calendar.reminderMinuteOfDay,
                  ),
                ),
                onTap: remindersBusy
                    ? null
                    : () async {
                        final schedule = await showDialog<ReminderSchedule>(
                          context: context,
                          builder: (_) => _ReminderScheduleDialog(
                            daysBefore: calendar.reminderDaysBefore,
                            minuteOfDay: calendar.reminderMinuteOfDay,
                          ),
                        );
                        if (schedule == null || !context.mounted) return;
                        final failure = await ref
                            .read(recurringRemindersControllerProvider.notifier)
                            .schedule(schedule);
                        if (context.mounted) _report(context, failure);
                      },
              ),
            const _SectionHeader('Data'),
            ListTile(
              enabled: !busy,
              leading: busy
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calculate_outlined),
              title: const Text('Recalculate account balances'),
              subtitle: const Text(
                'Work every balance out again from its transactions. For '
                'after a restore, or when a total looks wrong.',
              ),
              onTap: busy ? null : () => _recalculate(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// When reminders come, as the Settings row says it: "The day before, at
/// 9:00 AM". The time in the phone's own 12- or 24-hour style. FR-SET-006.
String describeReminderSchedule(
  BuildContext context, {
  required int daysBefore,
  required int minuteOfDay,
}) {
  final time = TimeOfDay(
    hour: minuteOfDay ~/ 60,
    minute: minuteOfDay % 60,
  ).format(context);
  return '${_daysBeforeLabel(daysBefore)}, at $time';
}

String _daysBeforeLabel(int days) => switch (days) {
  0 => 'On the day',
  1 => 'The day before',
  _ => '$days days before',
};

/// Picks how many days before, and at what time, reminders come.
/// FR-SET-006.
///
/// Returns the new [ReminderSchedule], or null when cancelled. The day list
/// runs to `NotificationSettings.maxReminderDaysBefore`, so it offers only
/// what `SetReminderSchedule` accepts.
class _ReminderScheduleDialog extends StatefulWidget {
  const _ReminderScheduleDialog({
    required this.daysBefore,
    required this.minuteOfDay,
  });

  final int daysBefore;
  final int minuteOfDay;

  @override
  State<_ReminderScheduleDialog> createState() =>
      _ReminderScheduleDialogState();
}

class _ReminderScheduleDialogState extends State<_ReminderScheduleDialog> {
  late int _days = widget.daysBefore;
  late int _minute = widget.minuteOfDay;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: _minute ~/ 60, minute: _minute % 60);
    return AlertDialog(
      title: const Text('Remind me'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            initialValue: _days,
            decoration: const InputDecoration(labelText: 'When'),
            items: [
              for (
                var d = 0;
                d <= NotificationSettings.maxReminderDaysBefore;
                d++
              )
                DropdownMenuItem(value: d, child: Text(_daysBeforeLabel(d))),
            ],
            onChanged: (d) => setState(() => _days = d ?? _days),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.access_time),
            title: Text(time.format(context)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: time,
              );
              if (picked != null) {
                setState(() => _minute = picked.hour * 60 + picked.minute);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context)
              .pop(ReminderSchedule(daysBefore: _days, minuteOfDay: _minute)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A section label, in the style Material uses for grouped settings.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Asking for the base currency. Returns the code, or null on cancel.
class _BaseCurrencyDialog extends StatefulWidget {
  const _BaseCurrencyDialog({required this.initial});

  final String initial;

  @override
  State<_BaseCurrencyDialog> createState() => _BaseCurrencyDialogState();
}

class _BaseCurrencyDialogState extends State<_BaseCurrencyDialog> {
  late final TextEditingController _code = TextEditingController(
    text: widget.initial,
  );
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// The use case's own verdict, shown as the user types once they have
  /// tried to save.
  String? get _error =>
      _submitted ? SetBaseCurrency.validate(_code.text)?.message : null;

  void _save() {
    setState(() => _submitted = true);
    if (SetBaseCurrency.validate(_code.text) != null) return;
    Navigator.of(context).pop(_code.text.trim().toUpperCase());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Base currency'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 3,
          decoration: InputDecoration(
            labelText: 'Currency code',
            hintText: 'LKR',
            counterText: '',
            errorText: _error,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          // E-34: rates are per pair, so a new base means the rates to it
          // may not exist yet. Said here, where the choice is made.
          'Accounts in other currencies count towards your total only '
          'once a rate to this currency is entered under Exchange rates.',
          style: Theme.of(context).textTheme.bodySmall,
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

/// "1st", "2nd", "23rd", "28th".
String _ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}

/// Asking for a whole number. Returns it, or null on cancel.
///
/// The rule shown is the use case's own [validate], run as the user types
/// once they have tried to save — the same pattern as the base-currency
/// dialog, for the same reason.
class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.validate,
    this.help,
  });

  final String title;
  final String label;
  final int initial;
  final ValidationFailure? Function(int) validate;
  final String? help;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final TextEditingController _value = TextEditingController(
    text: '${widget.initial}',
  );
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _value.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  /// The typed number, or a value the use case will refuse when it is not
  /// a number at all — so the refusal is the use case's sentence either way.
  int get _number => int.tryParse(_value.text.trim()) ?? -1;

  String? get _error => _submitted ? widget.validate(_number)?.message : null;

  void _save() {
    setState(() => _submitted = true);
    if (widget.validate(_number) != null) return;
    Navigator.of(context).pop(_number);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _value,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.help,
        helperMaxLines: 3,
        errorText: _error,
      ),
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
