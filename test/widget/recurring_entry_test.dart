import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/recurring_rule_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/create_recurring_rule.dart';
import 'package:moneyora/features/transactions/presentation/pages/add_transaction_page.dart';
import 'package:moneyora/features/transactions/presentation/providers/recurring_catch_up.dart';
import 'package:moneyora/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:moneyora/injection.dart';

/// Records what `CreateRecurringRule` hands down.
class _Rules implements RecurringRuleRepository {
  Transaction? first;
  RecurringRule? rule;

  @override
  Future<Either<Failure, int>> create({
    required Transaction first,
    required RecurringRule rule,
  }) async {
    this.first = first;
    this.rule = rule;
    return const Right(1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Counts the catch-ups asked for, and runs none: the real one would open
/// the database.
class _CountingCatchUp extends RecurringCatchUp {
  static var runs = 0;

  @override
  void build() {}

  @override
  void run() => runs++;
}

/// E-13's recurring toggle on the entry screen. FR-EXP-008, FR-INC-004.
void main() {
  late _Rules rules;

  const categories = [
    CategoryOption(
      id: 1,
      name: 'Rent',
      icon: 'home',
      colorHex: '#C62828',
      isExpense: true,
    ),
    CategoryOption(
      id: 3,
      name: 'Salary',
      icon: 'wallet',
      colorHex: '#2E7D32',
      isExpense: false,
    ),
  ];
  const accounts = [AccountOption(id: 1, name: 'Cash', balanceCents: 0)];

  setUp(() {
    rules = _Rules();
    _CountingCatchUp.runs = 0;
  });

  Future<void> pumpEntry(WidgetTester tester, {Transaction? initial}) async {
    // A tall phone (360x1000 logical): the keypad takes most of an 800-high
    // screen, and the repeat section needs the list above it to scroll into.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          entryCategoriesProvider.overrideWith(
            (ref) => Stream<List<CategoryOption>>.value(categories),
          ),
          entryAccountsProvider.overrideWith(
            (ref) => Stream<List<AccountOption>>.value(accounts),
          ),
          createRecurringRuleProvider.overrideWith(
            (ref) async => CreateRecurringRule(rules),
          ),
          recurringCatchUpProvider.overrideWith(_CountingCatchUp.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AddTransactionPage(initial: initial),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillRent(WidgetTester tester) async {
    for (final key in '4500'.split('')) {
      await tapText(tester, key);
    }
    await tapText(tester, 'Rent');
  }

  final repeatToggle = find.byTooltip('Repeat');
  final saveButton = find.widgetWithText(FilledButton, 'Save');

  FilledButton save(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton);

  testWidgets('the schedule is hidden until Repeat is turned on', (
    tester,
  ) async {
    await pumpEntry(tester);

    expect(find.text('Repeats'), findsNothing);
    await tester.tap(repeatToggle);
    await tester.pumpAndSettle();

    expect(find.text('Repeats'), findsOneWidget);
    for (final label in [
      'Daily',
      'Weekly',
      'Monthly',
      'Yearly',
      'Every N days',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('No end date'), findsOneWidget);
    expect(find.byTooltip('Stop repeating'), findsOneWidget);
  });

  testWidgets('saving creates the entry and its monthly rule, then asks for '
      'a catch-up', (tester) async {
    await pumpEntry(tester);
    await fillRent(tester);
    await tester.tap(repeatToggle);
    await tester.pumpAndSettle();

    final today = DateTime.now();
    expect(
      find.text(
        today.day > RecurringRule.maxDayOfMonth
            ? 'A monthly repeat can fall on the 1st to the 28th, so it '
                  'lands in every month.'
            : 'Monthly on the ${_ordinal(today.day)}',
      ),
      findsOneWidget,
    );
    if (today.day > RecurringRule.maxDayOfMonth) {
      // The default is monthly; on the 29th–31st it cannot be saved, which
      // the next test covers. Switch to weekly to save here.
      await tapText(tester, 'Weekly');
    }

    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(rules.first!.amountCents, 450000);
    expect(rules.first!.categoryId, 1);
    expect(rules.first!.type, TransactionType.expense);
    expect(
      rules.rule!.frequency,
      today.day > RecurringRule.maxDayOfMonth
          ? RecurrenceFrequency.weekly
          : RecurrenceFrequency.monthly,
    );
    expect(_CountingCatchUp.runs, 1);
    // Popped back to the opener.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a monthly start past the 28th is refused before saving (E-03)', (
    tester,
  ) async {
    await pumpEntry(tester);
    await fillRent(tester);
    await tester.tap(repeatToggle);
    await tester.pumpAndSettle();

    // Back to a month with a 31st: at most two months back from any month.
    await tapText(tester, 'Today');
    for (var i = 0; i < 3 && find.text('31').evaluate().isEmpty; i++) {
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
    }
    await tapText(tester, '31');
    await tapText(tester, 'OK');

    expect(
      find.text(
        'A monthly repeat can fall on the 1st to the 28th, so it lands in '
        'every month.',
      ),
      findsOneWidget,
    );
    expect(save(tester).onPressed, isNull);

    // Any other frequency is fine from the 31st.
    await tapText(tester, 'Yearly');
    expect(save(tester).onPressed, isNotNull);
  });

  testWidgets('every N days takes its interval from the field', (tester) async {
    await pumpEntry(tester);
    await fillRent(tester);
    await tester.tap(repeatToggle);
    await tester.pumpAndSettle();

    await tapText(tester, 'Every N days');

    // The field is below the fold of a lazily built list: scroll to it.
    final field = find.widgetWithText(TextField, 'Every how many days');
    await tester.dragUntilVisible(
      field,
      find.byType(ListView),
      const Offset(0, -80),
    );
    Future<void> typeInterval(String days) async {
      await tester.enterText(field, days);
      await tester.pumpAndSettle();
    }

    await typeInterval('10');
    expect(find.text('Every 10 days'), findsOneWidget);

    await typeInterval('0');
    expect(
      find.text('A custom repeat needs an interval of at least one day.'),
      findsOneWidget,
    );
    expect(save(tester).onPressed, isNull);

    await typeInterval('14');
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(rules.rule!.frequency, RecurrenceFrequency.customDays);
    expect(rules.rule!.intervalDays, 14);
  });

  testWidgets('income repeats too (FR-INC-004)', (tester) async {
    await pumpEntry(tester);
    await tapText(tester, 'Income');
    for (final key in '2500'.split('')) {
      await tapText(tester, key);
    }
    await tapText(tester, 'Salary');
    await tester.tap(repeatToggle);
    await tester.pumpAndSettle();
    await tapText(tester, 'Weekly');

    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(rules.first!.type, TransactionType.income);
    expect(rules.rule!.frequency, RecurrenceFrequency.weekly);
  });

  testWidgets('an edit offers no Repeat: a rule starts with a new entry', (
    tester,
  ) async {
    await pumpEntry(
      tester,
      initial: Transaction(
        id: 4,
        accountId: 1,
        categoryId: 1,
        amountCents: 450000,
        type: TransactionType.expense,
        date: DateTime(2026, 3, 5),
      ),
    );

    expect(repeatToggle, findsNothing);
  });
}

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}
