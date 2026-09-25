import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/recurring_rule.dart';
import '../repositories/recurring_rule_repository.dart';

/// Watches every recurring rule, active and stopped, with the entry each
/// copies. FR-EXP-008, FR-INC-004.
///
/// The rules list's one read. Ordered for that list: rules that still post
/// first, by the date they next post; then stopped ones, most recently
/// started first. The order is decided here rather than in SQL because
/// "still posts" is [RecurringRule.statusOn]'s rule, and a second version
/// of it in a query would drift from the one the list labels rows with.
class WatchRecurringRules
    implements StreamUseCase<List<RecurringSeries>, DateTime> {
  /// Creates the use case.
  const WatchRecurringRules(this._repository);

  final RecurringRuleRepository _repository;

  /// Watches the rules, ordered as of [params] — today.
  @override
  Stream<Either<Failure, List<RecurringSeries>>> call(DateTime params) =>
      _repository.watchAll().map(
        (result) => result.map((series) => order(series, params)),
      );

  /// [series] in the list's order on [today]. Public and static so the
  /// order is tested without a stream.
  static List<RecurringSeries> order(
    List<RecurringSeries> series,
    DateTime today,
  ) {
    bool posts(RecurringSeries s) => switch (s.rule.statusOn(today)) {
      RecurrenceStatus.active || RecurrenceStatus.overdue => true,
      _ => false,
    };
    return [...series]..sort((a, b) {
      final aPosts = posts(a);
      if (aPosts != posts(b)) return aPosts ? -1 : 1;
      final byDate = aPosts
          ? a.rule.nextDueDate.compareTo(b.rule.nextDueDate)
          : b.rule.startDate.compareTo(a.rule.startDate);
      return byDate != 0 ? byDate : (a.rule.id ?? 0).compareTo(b.rule.id ?? 0);
    });
  }
}
