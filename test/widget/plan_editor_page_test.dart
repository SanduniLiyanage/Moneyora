@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/budget_alerts_switch.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/ports/notification_settings.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_line.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/save_built_plan.dart';
import 'package:moneyora/features/money_plan/presentation/pages/plan_editor_page.dart';
import 'package:moneyora/features/money_plan/presentation/providers/money_plan_providers.dart';
import 'package:moneyora/injection.dart';

import 'large_text.dart';

/// The plan editor: building a plan by hand, and editing a generated one
/// before it is saved. E-39, FR-PLN-011.
void main() {
  final october = PlanPeriod.month(2026, 10);

  CategoryOption category(int id, String name) => CategoryOption(
    id: id,
    name: name,
    icon: 'tag',
    colorHex: '#3F51B5',
    isExpense: true,
  );

  final categories = [
    category(1, 'Food'),
    category(2, 'Transport'),
    category(3, 'Bills'),
  ];

  /// Rent as the generator suggested it: Rs 45,000, Fixed, High.
  const rent = PlanLine(
    categoryId: 3,
    categoryName: 'Bills',
    amountCents: 4500000,
    suggestion: PlanSuggestion(
      amountCents: 4500000,
      confidence: ConfidenceLevel.high,
      type: ExpenseType.fixed,
    ),
  );

  Widget boot(
    PlanEditorArgs args, {
    _Repository? repository,
    NotificationSettings? notifications,
    _Switch? alerts,
  }) => ProviderScope(
    overrides: [
      planCategoriesProvider.overrideWith((ref) => Stream.value(categories)),
      saveBuiltPlanProvider.overrideWith(
        (ref) async => SaveBuiltPlan(repository ?? _Repository()),
      ),
      if (notifications != null)
        notificationSettingsProvider.overrideWith(
          (ref) => Stream.value(notifications),
        ),
      if (alerts != null)
        budgetAlertsSwitchProvider.overrideWith((ref) async => alerts),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: Routes.home,
        routes: [
          GoRoute(
            path: Routes.home,
            // Watches the notification settings as the app's alert watcher
            // does, so the editor finds them loaded.
            builder: (context, state) => Consumer(
              builder: (context, ref, _) {
                if (notifications != null) {
                  ref.watch(notificationSettingsProvider);
                }
                return Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () =>
                          context.push(Routes.planEditor, extra: args),
                      child: const Text('open'),
                    ),
                  ),
                );
              },
            ),
          ),
          GoRoute(
            path: Routes.planEditor,
            builder: (context, state) =>
                PlanEditorPage(args: state.extra! as PlanEditorArgs),
          ),
          GoRoute(
            path: Routes.activePlan,
            builder: (context, state) =>
                const Scaffold(body: Text('active plan stub')),
          ),
          GoRoute(
            path: Routes.plans,
            builder: (context, state) =>
                const Scaffold(body: Text('plans stub')),
          ),
        ],
      ),
    ),
  );

  Future<void> open(
    WidgetTester tester,
    PlanEditorArgs args, {
    _Repository? repository,
    NotificationSettings? notifications,
    _Switch? alerts,
  }) async {
    await tester.pumpWidget(
      boot(
        args,
        repository: repository,
        notifications: notifications,
        alerts: alerts,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(String name) => find.widgetWithText(TextField, name);

  group('built by hand', () {
    testWidgets('starts from every expense category, empty', (tester) async {
      await open(tester, PlanEditorArgs(period: october));

      expect(find.text('Build your plan'), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      for (final name in ['Food', 'Transport', 'Bills']) {
        expect(field(name), findsOneWidget);
      }
      expect(find.text('Rs0.00'), findsOneWidget);
      expect(find.textContaining('Leave the rest empty'), findsOneWidget);
    });

    testWidgets('the total and the daily figure follow what is typed', (
      tester,
    ) async {
      await open(tester, PlanEditorArgs(period: october));

      await tester.enterText(field('Food'), '31000');
      await tester.enterText(field('Transport'), '9,000');
      await tester.pump();

      expect(find.text('Rs40,000.00'), findsOneWidget);
      // 31,000 over October's 31 days.
      expect(find.text('Rs1,000.00 a day'), findsOneWidget);
    });

    testWidgets('saves the categories with an amount, and opens the plan', (
      tester,
    ) async {
      final repository = _Repository();
      await open(
        tester,
        PlanEditorArgs(period: october),
        repository: repository,
      );

      await tester.enterText(field('Food'), '30000');
      await tester.enterText(field('Bills'), '45000');
      await tester.tap(find.text('Save plan'));
      await tester.pumpAndSettle();

      expect(find.text('Name your plan'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final plan = repository.saved!;
      expect(plan.name, 'October 2026');
      expect(plan.isActive, isTrue);
      expect(plan.totalBudgetCents, 7500000);
      expect(plan.allocations.map((a) => a.categoryName), ['Food', 'Bills']);
      expect(plan.allocations.every((a) => a.isUserModified), isTrue);
      expect(find.text('active plan stub'), findsOneWidget);
    });

    testWidgets('nothing typed: says what is missing, and saves nothing', (
      tester,
    ) async {
      final repository = _Repository();
      await open(
        tester,
        PlanEditorArgs(period: october),
        repository: repository,
      );

      await tester.tap(find.text('Save plan'));
      await tester.pumpAndSettle();

      expect(find.text('Give at least one category an amount.'), findsWidgets);
      expect(find.text('Name your plan'), findsNothing);
      expect(repository.saved, isNull);
    });

    testWidgets('an amount that is not money is pointed at', (tester) async {
      await open(tester, PlanEditorArgs(period: october));

      await tester.enterText(field('Food'), 'lots');
      await tester.pump();

      expect(find.text('Type an amount, like 2500'), findsOneWidget);
    });

    testWidgets('a category can be removed', (tester) async {
      await open(tester, PlanEditorArgs(period: october));

      await tester.tap(find.byTooltip('Remove Transport'));
      await tester.pumpAndSettle();

      expect(field('Transport'), findsNothing);
      expect(field('Food'), findsOneWidget);
    });

    testWidgets('leaving with amounts typed asks first', (tester) async {
      await open(tester, PlanEditorArgs(period: october));
      await tester.enterText(field('Food'), '100');
      await tester.pump();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Build your plan'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('holds at the largest font on a 320dp phone. SRS §4.1', (
      tester,
    ) async {
      useLargeTextOnSmallPhone(tester);
      await open(tester, PlanEditorArgs(period: october));

      // Below the fold at this size: the list builds lazily.
      await tester.scrollUntilVisible(
        field('Food'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(field('Food'), '1234567');
      await tester.pump();
      await scrollToEnd(tester);
      expect(find.text('Add a category'), findsOneWidget);
    });
  });

  group('a generated plan, edited. FR-PLN-011', () {
    PlanEditorArgs generated() => PlanEditorArgs(
      period: october,
      lines: const [rent],
      suggestedTotalCents: 4500000,
    );

    testWidgets('starts from the suggestion, and compares against it', (
      tester,
    ) async {
      await open(tester, generated());

      expect(find.text('Edit your plan'), findsOneWidget);
      expect(field('Bills'), findsOneWidget);
      expect(field('Food'), findsNothing);
      expect(find.text('The same as suggested.'), findsOneWidget);

      await tester.enterText(field('Bills'), '50000');
      await tester.pump();

      expect(
        find.text('Rs5,000.00 more than the suggested Rs45,000.00.'),
        findsOneWidget,
      );
      expect(find.textContaining('Suggested Rs45,000.00'), findsOneWidget);
    });

    testWidgets('a category can be added from the ones not in it', (
      tester,
    ) async {
      await open(tester, generated());

      await tester.tap(find.text('Add a category'));
      await tester.pumpAndSettle();
      // Bills is in the plan already, so it is not offered.
      expect(find.widgetWithText(ListTile, 'Bills'), findsNothing);

      await tester.tap(find.widgetWithText(ListTile, 'Food'));
      await tester.pumpAndSettle();
      expect(field('Food'), findsOneWidget);
    });

    testWidgets('saves the edit, keeping where each figure came from', (
      tester,
    ) async {
      final repository = _Repository();
      await open(tester, generated(), repository: repository);

      await tester.enterText(field('Bills'), '50000');
      await tester.tap(find.text('Save plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final row = repository.saved!.allocations.single;
      expect(row.allocatedCents, 5000000);
      expect(row.expenseType, ExpenseType.fixed);
      expect(row.confidence, ConfidenceLevel.high);
      expect(row.isUserModified, isTrue);
    });
  });

  group('budget alerts, offered on save. FR-SET-007', () {
    const off = NotificationSettings();

    Future<void> saveWithFood(WidgetTester tester) async {
      await tester.enterText(field('Food'), '30000');
      await tester.tap(find.text('Save plan'));
      await tester.pumpAndSettle();
    }

    testWidgets('while they are off: offered, ticked, and turned on', (
      tester,
    ) async {
      final alerts = _Switch();
      await open(
        tester,
        PlanEditorArgs(period: october),
        notifications: off,
        alerts: alerts,
      );
      await saveWithFood(tester);

      expect(find.text('Alert me near and over each limit'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(alerts.turnedOn, 1);
      expect(find.textContaining('Budget alerts are on'), findsOneWidget);
      expect(find.text('active plan stub'), findsOneWidget);
    });

    testWidgets('unticked, they stay off', (tester) async {
      final alerts = _Switch();
      await open(
        tester,
        PlanEditorArgs(period: october),
        notifications: off,
        alerts: alerts,
      );
      await saveWithFood(tester);

      await tester.tap(find.text('Alert me near and over each limit'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(alerts.turnedOn, 0);
    });

    testWidgets('a refused permission says where it is now', (tester) async {
      final alerts = _Switch(
        refusal: const PermissionFailure('Allow them in Settings.'),
      );
      await open(
        tester,
        PlanEditorArgs(period: october),
        notifications: off,
        alerts: alerts,
      );
      await saveWithFood(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Allow them in Settings.'), findsOneWidget);
    });

    testWidgets('already on: not offered', (tester) async {
      await open(
        tester,
        PlanEditorArgs(period: october),
        notifications: const NotificationSettings(budgetAlertsEnabled: true),
        alerts: _Switch(),
      );
      await saveWithFood(tester);

      expect(find.text('Alert me near and over each limit'), findsNothing);
    });

    testWidgets('a plan kept for later: not offered', (tester) async {
      await open(
        tester,
        PlanEditorArgs(period: october),
        notifications: off,
        alerts: _Switch(),
      );
      await saveWithFood(tester);

      await tester.tap(find.text('Track it now'));
      await tester.pump();

      expect(find.text('Alert me near and over each limit'), findsNothing);
    });
  });
}

/// Counts the times alerts were turned on, or refuses as the platform may.
class _Switch implements BudgetAlertsSwitch {
  _Switch({this.refusal});

  final Failure? refusal;
  int turnedOn = 0;

  @override
  Future<Either<Failure, Unit>> turnOn() async {
    turnedOn++;
    return refusal == null ? const Right(unit) : Left(refusal!);
  }
}

/// Records the plan saved; nothing else is reached from the editor.
class _Repository implements MoneyPlanRepository {
  MoneyPlan? saved;

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) async {
    saved = plan;
    return const Right(1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
