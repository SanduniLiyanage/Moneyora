import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/encryption_key_store.dart';
import 'package:moneyora/core/usecases/usecase.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/backup/domain/usecases/restore_backup.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/receipt_image_vault.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/injection.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// Back up, clear, restore on another phone — through the app's own wiring.
/// FR-BAK-001, FR-BAK-005, FR-SET-009, E-38.
///
/// `backup_local_datasource_test.dart` proves the file format and the
/// restore's transaction against one database. This walks what the
/// emulator pass walked by hand, provider to provider: an expense with a
/// photo, a backup, a clear, and a restore onto a second phone with its
/// own database file, its own key and its own vault — so the photo has to
/// be decrypted and sealed again, not copied. Everything below `data/` is
/// real; only where the files live and where the key is kept are chosen.
void main() {
  sqfliteFfiInit();

  late Directory root;
  final databases = <String>[];

  setUp(() async => root = await Directory.systemTemp.createTemp('moneyora'));
  tearDown(() async {
    for (final name in databases) {
      final base = await databaseFactoryFfi.getDatabasesPath();
      await databaseFactoryFfi.deleteDatabase('$base/$name');
    }
    databases.clear();
    await root.delete(recursive: true);
  });

  /// One phone: its own database file, keychain and documents directory.
  ProviderContainer phone(String name) {
    final dir = Directory('${root.path}/$name')..createSync();
    final keys = InMemoryKeyStore();
    // Named under the factory's own directory, which the helper prefixes.
    final database =
        '${root.uri.pathSegments.lastWhere((s) => s.isNotEmpty)}'
        '-$name.db';
    databases.add(database);
    final container = ProviderContainer(
      overrides: [
        databaseFactoryProvider.overrideWithValue(databaseFactoryFfi),
        databaseNameProvider.overrideWithValue(database),
        encryptionKeyStoreProvider.overrideWithValue(keys),
        receiptImageVaultProvider.overrideWithValue(
          EncryptedReceiptImageVault(
            keyStore: keys,
            documents: () async => dir,
            temporary: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<Transaction>> ledger(ProviderContainer c) async {
    final watch = await c.read(watchTransactionsProvider.future);
    final rows = await watch(const TransactionFilter()).first;
    return rows.getOrElse((f) => fail('$f'));
  }

  Future<int> balance(ProviderContainer c) async {
    final watch = await c.read(watchAccountsProvider.future);
    final accounts = await watch(false).first;
    return accounts
        .getOrElse((f) => fail('$f'))
        .singleWhere((Account a) => a.id == 1)
        .currentBalanceCents;
  }

  test(
    'an expense and its photo survive backup, clear and another phone',
    () async {
      final first = phone('first');
      final photo = Uint8List.fromList(List.generate(4096, (i) => i % 251));

      // An expense with a photo, the way the entry screen keeps one.
      final kept = await first
          .read(receiptImageVaultProvider)
          .keepBytes(photo, extension: '.jpg');
      final add = await first.read(addTransactionProvider.future);
      final added = await add(
        Transaction(
          accountId: 1,
          categoryId: 1,
          amountCents: 125000,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 25),
          note: 'Groceries',
          receiptImagePath: kept,
        ),
      );
      expect(added.isRight(), isTrue, reason: '$added');
      final balanceBefore = await balance(first);

      // Back up.
      final create = await first.read(createBackupProvider.future);
      final backup = (await create('testpass123')).getOrElse((f) => fail('$f'));
      expect(backup.name, endsWith('.mora'));

      // Clear: the ledger and the photo both go, and the count says so.
      final clear = await first.read(clearAllDataProvider.future);
      expect((await clear(const NoParams())).isRight(), isTrue);
      expect(await ledger(first), isEmpty);
      expect(await first.read(receiptImageVaultProvider).read(kept), isNull);

      // Restore on a second phone, which has never seen the first one's key.
      final second = phone('second');
      final restore = await second.read(restoreBackupProvider.future);
      final wrong = await restore(
        RestoreRequest(bytes: backup.bytes, password: 'not the one'),
      );
      expect(wrong.isLeft(), isTrue);
      expect(
        await ledger(second),
        isEmpty,
        reason: 'a refusal changes nothing',
      );

      final restored = await restore(
        RestoreRequest(bytes: backup.bytes, password: 'testpass123'),
      );
      expect(restored.getOrElse((f) => fail('$f')).transactionCount, 1);
      // E-18: the screen recounts every balance after a restore.
      final recompute = await second.read(
        recomputeAllAccountBalancesProvider.future,
      );
      expect((await recompute(const NoParams())).isRight(), isTrue);

      final rows = await ledger(second);
      expect(rows.single.amountCents, 125000);
      expect(rows.single.note, 'Groceries');
      expect(await balance(second), balanceBefore);

      // The photo came across decrypted and was sealed again under the
      // second phone's key: it opens there, at a path of its own.
      final path = rows.single.receiptImagePath!;
      expect(path, isNot(kept));
      expect(await second.read(receiptImageVaultProvider).read(path), photo);
      final onDisk = await File(path).readAsBytes();
      expect(onDisk.sublist(0, 4), isNot(photo.sublist(0, 4)));

      // The home screen's count follows the restore (E-22's empty states).
      final summary = await second.read(databaseSummaryProvider.future);
      expect(summary.transactions, 1);
    },
  );
}
