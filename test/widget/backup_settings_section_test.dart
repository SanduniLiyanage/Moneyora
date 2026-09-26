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
import 'package:moneyora/features/backup/domain/entities/restore_summary.dart';
import 'package:moneyora/features/backup/domain/repositories/backup_repository.dart';
import 'package:moneyora/features/backup/presentation/widgets/backup_settings_section.dart';
import 'package:moneyora/injection.dart';

/// The rows driven as a person drives them, over the real use cases and
/// controller, with the repository and the platform's dialogs faked.
void main() {
  late _FakeBackups backups;
  late _FakeFiles files;
  late _FakeRecompute recompute;

  setUp(() {
    backups = _FakeBackups();
    files = _FakeFiles();
    recompute = _FakeRecompute();
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
