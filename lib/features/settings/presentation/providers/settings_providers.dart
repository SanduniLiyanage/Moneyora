/// Presentation state for the settings feature.
///
/// These talk to **use cases**, never to a repository or a datasource, which
/// is the rule `scripts/check_architecture.sh` enforces and the reason a
/// screen can be tested by overriding one provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../injection.dart';

/// Recalculating every account balance from history. E-18.
///
/// The one Settings action that is a repair rather than a preference. It is
/// reached from here and from nowhere else on purpose: reconciliation reads
/// every transaction of every account, and the E-18 addendum keeps that scan
/// off the launch path so NFR-PER-001's cold start does not pay for a repair
/// nobody asked for.
class RecalculateBalancesController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Re-derives every balance.
  ///
  /// Returns the failure rather than true/false, because the caller needs the
  /// sentence to show and not merely the fact that something went wrong.
  Future<Failure?> run() async {
    state = const AsyncValue<void>.loading();
    final recompute = await ref.read(
      recomputeAllAccountBalancesProvider.future,
    );
    final result = await recompute(const NoParams());
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return failure;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        return null;
      },
    );
  }
}

/// Controller for the recalculate-balances action.
final recalculateBalancesControllerProvider =
    AutoDisposeAsyncNotifierProvider<RecalculateBalancesController, void>(
      RecalculateBalancesController.new,
    );
