/// One "something was written" signal, shared by every datasource.
///
/// ## Why this exists
///
/// SQLite has no change notification, so nothing can tell a watching screen
/// *what* changed — only that something did, after which each watcher re-runs
/// its own query. Each datasource used to own that signal privately, which
/// worked only while a feature's writes were the sole thing that could move
/// its own rows.
///
/// That stopped being true at E-18. `accounts.current_balance_cents` is a
/// cache, and it is moved inside the same database transaction as the
/// `transactions` row that changes it — which means the write happens in the
/// **transactions** datasource and the changed row belongs to **accounts**. A
/// watcher listening only to the accounts datasource never learns its balance
/// moved, so the first screen to show one (FR-ACC-003's side-drawer) shows a
/// number that is correct exactly until the user adds an expense.
///
/// A shared bus is the smallest fix that does not put one feature's datasource
/// inside another's, which rule 4 of `check_architecture.sh` forbids and which
/// would be the wrong shape regardless.
///
/// ## Why it does not say what changed
///
/// Every listener re-runs its own query on any tick, so an account edit also
/// re-runs the transaction list's query. That is deliberate: the alternative is
/// a topic or table filter, which is more code, more to keep correct, and buys
/// nothing until a redundant query is measurably too slow. Writes are
/// user-initiated and therefore rare, and repositories already serialise their
/// re-reads. Revisit this if NFR-PER-006 work ever shows it mattering — adding
/// topics later is a change to this file and its two callers.
///
/// ## Ownership
///
/// Whoever constructs the bus closes it. A datasource handed one never closes
/// it, because the first datasource disposed would otherwise silence every
/// other one sharing it. A datasource handed nothing makes its own private bus
/// and does close that, which keeps a datasource constructed on its own — as
/// every unit test constructs one — behaving exactly as it did before.
library;

import 'dart:async';

/// A broadcast "the database changed" signal.
class DatabaseChangeBus {
  /// Creates a bus with no listeners.
  DatabaseChangeBus();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// Fires once after every successful write by any datasource sharing this.
  Stream<void> get changes => _controller.stream;

  /// Whether [close] has been called.
  bool get isClosed => _controller.isClosed;

  /// Announces a completed write.
  ///
  /// Silently does nothing once closed. A write that lands during teardown is
  /// not worth an exception on a stream nobody is listening to any more.
  void notify() {
    if (!_controller.isClosed) _controller.add(null);
  }

  /// Closes the signal. Only the owner calls this.
  Future<void> close() => _controller.close();
}
