import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/recurring_rule_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/delete_recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/usecases/pause_recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/usecases/resume_recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/usecases/watch_recurring_rules.dart';
import 'package:moneyora/features/transactions/presentation/pages/recurring_rules_page.dart';
import 'package:moneyora/features/transactions/presentation/providers/recurring_catch_up.dart';
import 'package:moneyora/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:moneyora/injection.dart';

/// The rules as the list reads them, and every write the sheet makes.
class _Rules implements RecurringRuleRepository {
  List<RecurringSeries> series = const [];
  Failure? failWrites;
  final paused = <int>[];
  final resumed = <(int, DateTime)>[];
  final deleted = <int>[];

  @override
  Stream<Either<Failure, List<RecurringSeries>>> watchAll() =>
      Stream.value(Right(series));

  Future<Either<Failure, Unit>> _write(void Function() record) async {
    if (failWrites case final f?) return Left(f);
    record();
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> pause(int ruleId) =>
      _write(() => paused.add(ruleId));

  @override
  Future<Either<Failure, Unit>> resume(int ruleId, DateTime nextDueDate) =>
      _write(() => resumed.add((ruleId, nextDueDate)));

  @override
  Future<Either<Failure, Unit>> delete(int ruleId) =>
      _write(() => deleted.add(ruleId));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _CountingCatchUp extends RecurringCatchUp {
  static var runs = 0;

  @override
  void build() {}

  @override
  void run() => runs++;
}

/// The rules list and its sheet. FR-EXP-008, FR-INC-004, E-36.
void main() {
  late _Rules rules;
  final today = DateTime(2026, 6, 20, 9);

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

  RecurringSeries series({
    int id = 5,
    int categoryId = 1,
    TransactionType type = TransactionType.expense,
    DateTime? next,
    DateTime? end,
    bool active = true,
    bool hasTemplate = true,
  }) => RecurringSeries(
    rule: RecurringRule(
      id: id,
      templateTransactionId: hasTemplate ? 9 : null,
      frequency: RecurrenceFrequency.monthly,
      dayOfMonth: 5,
      startDate: DateTime(2026, 1, 5),
      nextDueDate: next ?? DateTime(2026, 7, 5),
      endDate: end,
      isActive: active,
    ),
    template: hasTemplate
        ? Transaction(
            id: 9,
            accountId: 1,
            categoryId: categoryId,
            amountCents: 4500000,
            type: type,
            date: DateTime(2026, 1, 5),
          )
        : null,
  );

  setUp(() {
    rules = _Rules();
    _CountingCatchUp.runs = 0;
  });

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => today),
          entryCategoriesProvider.overrideWith(
            (ref) => Stream<List<CategoryOption>>.value(categories),
          ),
          watchRecurringRulesProvider.overrideWith(
            (ref) async => WatchRecurringRules(rules),
          ),
          pauseRecurringRuleProvider.overrideWith(
            (ref) async => PauseRecurringRule(rules),
          ),
          resumeRecurringRuleProvider.overrideWith(
            (ref) async => ResumeRecurringRule(rules),
          ),
          deleteRecurringRuleProvider.overrideWith(
            (ref) async => DeleteRecurringRule(rules),
          ),
          recurringCatchUpProvider.overrideWith(_CountingCatchUp.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RecurringRulesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with no rules, says what belongs here and how to add one', (
    tester,
  ) async {
    await pumpList(tester);

    expect(find.text('No repeating entries yet'), findsOneWidget);
    expect(find.textContaining('Tap Repeat'), findsOneWidget);
  });

  testWidgets('a row says what repeats, how often, and where it stands', (
    tester,
  ) async {
    rules.series = [
      series(),
      series(id: 6, categoryId: 3, type: TransactionType.income, active: false),
    ];
    await pumpList(tester);

    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(
      find.text('Monthly on the 5th\nNext on Jul 5, 2026'),
      findsOneWidget,
    );
    expect(find.text('Monthly on the 5th\nPaused'), findsOneWidget);
    expect(find.text('Rs45,000.00'), findsNWidgets(2));
  });

  testWidgets('an overdue rule says so', (tester) async {
    rules.series = [series(next: DateTime(2026, 6, 5))];
    await pumpList(tester);

    expect(find.textContaining('Overdue since Jun 5, 2026'), findsOneWidget);
  });

  testWidgets('a rule whose template is gone is named, and has no amount', (
    tester,
  ) async {
    rules.series = [series(hasTemplate: false)];
    await pumpList(tester);

    expect(find.text('Deleted entry'), findsOneWidget);
    expect(
      find.textContaining('Stopped: its first entry was deleted'),
      findsOneWidget,
    );
    expect(find.textContaining('Rs'), findsNothing);
  });

  testWidgets('Pause stops a running rule and closes the sheet', (
    tester,
  ) async {
    rules.series = [series()];
    await pumpList(tester);

    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsNothing);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(rules.paused, [5]);
    expect(find.text('Pause'), findsNothing, reason: 'the sheet closed');
  });

  testWidgets('Resume starts a paused rule from today, then asks for a '
      'catch-up', (tester) async {
    rules.series = [series(next: DateTime(2026, 2, 5), active: false)];
    await pumpList(tester);

    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsNothing);
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    // The paused months are stepped over, not posted.
    expect(rules.resumed, [(5, DateTime(2026, 7, 5))]);
    expect(_CountingCatchUp.runs, 1);
  });

  testWidgets('Delete asks first, and says the entries stay (E-36)', (
    tester,
  ) async {
    rules.series = [series()];
    await pumpList(tester);

    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this repeat?'), findsOneWidget);
    expect(find.textContaining('stay in your history'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(rules.deleted, isEmpty);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pumpAndSettle();

    expect(rules.deleted, [5]);
  });

  testWidgets('an ended rule offers only Delete', (tester) async {
    rules.series = [series(end: DateTime(2026, 6, 30))];
    await pumpList(tester);

    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Resume'), findsNothing);
  });

  testWidgets("a failure is shown in the use case's words, and the sheet "
      'stays', (tester) async {
    rules
      ..series = [series()]
      ..failWrites = const CacheFailure('Could not pause the repeat.');
    await pumpList(tester);

    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(find.text('Could not pause the repeat.'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('a failed read says so', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => today),
          entryCategoriesProvider.overrideWith(
            (ref) => Stream<List<CategoryOption>>.value(categories),
          ),
          watchRecurringRulesProvider.overrideWith(
            (ref) async => WatchRecurringRules(_FailingRules()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RecurringRulesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not read.'), findsOneWidget);
  });
}

class _FailingRules extends _Rules {
  @override
  Stream<Either<Failure, List<RecurringSeries>>> watchAll() =>
      Stream.value(const Left(CacheFailure('Could not read.')));
}
