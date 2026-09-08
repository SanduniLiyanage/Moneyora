/// Presentation state for the accounts feature.
///
/// These talk to **use cases**, never to a repository or a datasource, which
/// is the rule `scripts/check_architecture.sh` enforces and the reason a
/// screen can be tested by overriding one provider.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../injection.dart';
import '../../domain/entities/account.dart';

/// The accounts, kept live, archived ones included only when asked.
///
/// A `StreamProvider` rather than a future because a balance is the most
/// derived thing on any screen: it moves whenever a transaction is written
/// anywhere, and a screen that read it once would be wrong by the time the
/// user looked back at it.
///
/// That only works because `injection.dart` hands both datasources one
/// `DatabaseChangeBus` — the balance is moved by the *transactions*
/// datasource, so without the shared signal this stream would never re-read
/// after an expense. See `core/database/database_change_bus.dart`.
final accountsProvider = StreamProvider.family<List<Account>, bool>((
  ref,
  includeArchived,
) {
  return Stream.fromFuture(ref.watch(watchAccountsProvider.future))
      .asyncExpand((watchAccounts) => watchAccounts(includeArchived))
      // A `Left` goes down the error channel so it arrives as
      // `AsyncValue.error` and each screen handles it in the branch its
      // `switch` already has. `sink.addError` rather than `throw`: a `Failure`
      // is a value, not an exception, and ARCHITECTURE.md §3 keeps those two
      // vocabularies apart deliberately.
      .transform(
        StreamTransformer<
          Either<Failure, List<Account>>,
          List<Account>
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});
