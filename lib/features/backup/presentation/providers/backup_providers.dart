/// Presentation state for backup and restore. FR-BAK-001, FR-BAK-005,
/// FR-SET-009.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/usecases/usecase.dart';
import '../../../../injection.dart';
import '../../domain/usecases/restore_backup.dart';

/// What a backup or restore came to, as the sentence the screen shows.
typedef BackupOutcome = ({bool done, String message});

/// Makes a backup and saves it where the user chooses, or restores one.
///
/// Each method answers with the sentence to show, including a failure's own
/// — the use cases and the datasource word every refusal, and this only
/// carries it.
class BackupController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Seals everything under [password] and asks where to save it.
  Future<BackupOutcome> backUp(String password) async {
    state = const AsyncValue<void>.loading();
    final create = await ref.read(createBackupProvider.future);
    final result = await create(password);

    final BackupOutcome outcome = await result.match(
      (failure) async => (done: false, message: failure.message),
      (file) async => await ref.read(backupFileGatewayProvider).save(file)
          ? (done: true, message: 'Backup saved as ${file.name}.')
          : (done: false, message: 'The backup was not saved.'),
    );
    state = const AsyncValue<void>.data(null);
    return outcome;
  }

  /// Replaces everything with the backup [bytes], opened with [password],
  /// then works every balance out again from the restored transactions —
  /// E-18's second caller, the one its addendum left to the restore.
  Future<BackupOutcome> restore(Uint8List bytes, String password) async {
    state = const AsyncValue<void>.loading();
    final restore = await ref.read(restoreBackupProvider.future);
    final result = await restore(
      RestoreRequest(bytes: bytes, password: password),
    );

    final BackupOutcome outcome = await result.match(
      (failure) async => (done: false, message: failure.message),
      (summary) async {
        final recompute = await ref.read(
          recomputeAllAccountBalancesProvider.future,
        );
        await recompute(const NoParams());
        final count = summary.transactionCount;
        return (
          done: true,
          message:
              'Restored $count ${count == 1 ? 'transaction' : 'transactions'} '
              'from a backup made on '
              '${DateFormat.yMMMd().format(summary.backedUpAt.toLocal())}.',
        );
      },
    );
    state = const AsyncValue<void>.data(null);
    return outcome;
  }
}

/// Controller for the backup rows.
final backupControllerProvider =
    AutoDisposeAsyncNotifierProvider<BackupController, void>(
      BackupController.new,
    );
