import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/core/usecases/usecase.dart';
import 'package:moneyora/features/accounts/domain/usecases/recompute_all_account_balances.dart';
import 'package:moneyora/features/backup/data/datasources/backup_file_gateway.dart';
import 'package:moneyora/features/backup/domain/entities/backup_file.dart';
import 'package:moneyora/features/backup/domain/entities/backup_status.dart';
import 'package:moneyora/features/backup/domain/entities/restore_summary.dart';
import 'package:moneyora/features/backup/domain/repositories/backup_repository.dart';
import 'package:moneyora/features/backup/presentation/providers/backup_reminder_watcher.dart';
import 'package:moneyora/features/backup/presentation/widgets/backup_settings_section.dart';
import 'package:moneyora/injection.dart';

/// The rows driven as a person drives them, over the real use cases and
/// controller, with the repository and the platform's dialogs faked.
void main() {
  late _FakeBackups backups;
  late _FakeFiles files;
  late _FakeRecompute recompute;
  late _FakeReminders reminders;

  setUp(() {
    backups = _FakeBackups();
    files = _FakeFiles();
    recompute = _FakeRecompute();
    reminders = _FakeReminders();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupRepositoryProvider.overrideWith((ref) async => backups),
          backupFileGatewayProvider.overrideWithValue(files),
          recomputeAllAccountBalancesProvider.overrideWith(
            (ref) async => recompute,
          ),
          backupReminderWatcherProvider.overrideWith(() => reminders),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 27, 10)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: BackupSettingsSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> typePasswords(
    WidgetTester tester,
    String first, [
    String? second,
  ]) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, first);
    if (second != null) await tester.enterText(fields.last, second);
    await tester.pump();
  }

  group('backing up', () {
    testWidgets('asks for the password twice, then saves where chosen', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();

      await typePasswords(tester, 'long enough', 'long enough');
      await tester.tap(find.text('Back up'));
      await tester.pumpAndSettle();

      expect(backups.createdWith, 'long enough');
      expect(files.saved, _file);
      // FR-BAK-006: a saved backup puts the reminder off.
      expect(backups.savedAt, DateTime(2026, 9, 27, 10));
      expect(reminders.syncs, 1);
      expect(
        find.text('Backup saved as moneyora-2026-09-27.mora.'),
        findsOneWidget,
      );
    });

    testWidgets('refuses two different passwords and a short one', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();

      await typePasswords(tester, 'long enough', 'long enougj');
      await tester.tap(find.text('Back up'));
      await tester.pumpAndSettle();
      expect(find.text('The two passwords are different.'), findsOneWidget);

      await typePasswords(tester, 'short', 'short');
      await tester.pump();
      expect(find.textContaining('Use at least 8 characters.'), findsOneWidget);
      expect(backups.createdWith, isNull);
    });

    testWidgets('says so when the save is cancelled', (tester) async {
      files.saveAnswers = false;
      await pump(tester);
      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();
      await typePasswords(tester, 'long enough', 'long enough');
      await tester.tap(find.text('Back up'));
      await tester.pumpAndSettle();

      expect(find.text('The backup was not saved.'), findsOneWidget);
      // Abandoned in the dialog, it protects nothing and puts nothing off.
      expect(backups.savedAt, isNull);
      expect(reminders.syncs, 0);
    });
  });

  group('exporting. FR-RPT-007', () {
    testWidgets('saves the CSV where chosen', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Export transactions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spreadsheet (CSV)'));
      await tester.pumpAndSettle();

      expect(files.saved, _csv);
      expect(
        find.text('Exported as moneyora-transactions-2026-09-27.csv.'),
        findsOneWidget,
      );
    });

    testWidgets('or the PDF', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Export transactions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();

      expect(files.saved, _pdf);
      expect(
        find.text('Exported as moneyora-transactions-2026-09-27.pdf.'),
        findsOneWidget,
      );
    });

    testWidgets('writes nothing when the choice is dismissed', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Export transactions'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(files.saved, isNull);
    });
  });

  group('clearing. FR-SET-009', () {
    testWidgets('clears only once confirmed, and says what happened', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Clear all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backups.cleared, 0);

      await tester.tap(find.text('Clear all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear everything'));
      await tester.pumpAndSettle();

      expect(backups.cleared, 1);
      expect(
        find.text(
          'Everything was cleared. Moneyora is as it was on first open.',
        ),
        findsOneWidget,
      );
    });
  });

  group('restoring', () {
    Future<void> restoreWith(WidgetTester tester, String password) async {
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();
      expect(find.text('Replace everything on this phone?'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      await typePasswords(tester, password);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
    }

    testWidgets('replaces, recounts every balance, and says what came '
        'back', (tester) async {
      await pump(tester);

      await restoreWith(tester, 'long enough');

      expect(backups.restored, (_file.bytes, 'long enough'));
      expect(recompute.runs, 1);
      expect(
        find.text(
          'Restored 42 transactions from a backup made on Sep 27, 2026.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('changes nothing when the replace is declined', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(backups.restored, isNull);
    });

    testWidgets("shows the refusal in the backup's own words, and recounts "
        'nothing', (tester) async {
      backups.restoreFails = const EncryptionFailure(
        'That password does not open this backup.',
      );
      await pump(tester);

      await restoreWith(tester, 'wrong');

      expect(
        find.text('That password does not open this backup.'),
        findsOneWidget,
      );
      expect(recompute.runs, 0);
    });

    testWidgets('does nothing when no file is chosen', (tester) async {
      files.picked = null;
      await pump(tester);
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();

      expect(find.text('Replace everything on this phone?'), findsNothing);
    });
  });
}

final _file = BackupFile(
  name: 'moneyora-2026-09-27.mora',
  bytes: Uint8List.fromList([1, 2, 3]),
);

class _FakeBackups implements BackupRepository {
  DateTime? savedAt;
  int cleared = 0;
  String? createdWith;
  (Uint8List, String)? restored;
  Failure? restoreFails;

  @override
  Future<Either<Failure, BackupFile>> create(String password) async {
    createdWith = password;
    return Right(_file);
  }

  @override
  Future<Either<Failure, RestoreSummary>> restore(
    Uint8List bytes,
    String password,
  ) async {
    if (restoreFails case final failure?) return Left(failure);
    restored = (bytes, password);
    return Right(
      RestoreSummary(
        backedUpAt: DateTime(2026, 9, 27, 12),
        transactionCount: 42,
        photoCount: 1,
      ),
    );
  }

  @override
  Future<Either<Failure, Unit>> clearAll() async {
    cleared++;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, BackupFile>> exportTransactionsCsv() async =>
      Right(_csv);

  @override
  Future<Either<Failure, BackupFile>> exportTransactionsPdf() async =>
      Right(_pdf);

  @override
  Future<Either<Failure, BackupStatus>> status(DateTime now) async => Right(
    BackupStatus(lastSavedAt: null, firstSeenAt: now, transactionCount: 0),
  );

  @override
  Future<Either<Failure, Unit>> recordSaved(DateTime at) async {
    savedAt = at;
    return const Right(unit);
  }
}

class _FakeFiles implements BackupFileGateway {
  BackupFile? saved;
  bool saveAnswers = true;
  Uint8List? picked = _file.bytes;

  @override
  Future<bool> save(BackupFile file) async {
    if (saveAnswers) saved = file;
    return saveAnswers;
  }

  @override
  Future<Uint8List?> pick() async => picked;
}

class _FakeRecompute implements RecomputeAllAccountBalances {
  int runs = 0;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    runs++;
    return const Right(unit);
  }
}

final _csv = BackupFile(
  name: 'moneyora-transactions-2026-09-27.csv',
  bytes: Uint8List.fromList([4, 5]),
);

class _FakeReminders extends BackupReminderWatcher {
  int syncs = 0;

  @override
  void build() {}

  @override
  void sync() => syncs++;
}

final _pdf = BackupFile(
  name: 'moneyora-transactions-2026-09-27.pdf',
  bytes: Uint8List.fromList([6, 7]),
);
