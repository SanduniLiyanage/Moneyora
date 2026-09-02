import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/features/transactions/data/models/transaction_model.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';

/// Mapping is where silent data loss lives.
///
/// Nothing here needs a database, which is the point: the whole file runs in
/// milliseconds, so the encoding decisions get checked on every save rather
/// than at the end of an eight-minute Gradle build.
void main() {
  // Date-only, because `Transaction.date` is a date — the time of day lives in
  // `Transaction.time`. Round-tripping a date that carries a time is covered
  // separately, under 'date encoding'.
  final date = DateTime(2026, 9, 2);
  final createdAt = DateTime(2026, 9, 1, 8, 15);
  final now = DateTime(2026, 9, 2, 14, 30);

  TransactionModel expense({
    int? id = 7,
    List<TransactionSplit> parts = const [],
  }) => TransactionModel(
    id: id,
    accountId: 1,
    categoryId: 3,
    amountCents: 125000,
    type: TransactionType.expense,
    date: date,
    time: '14:30',
    note: 'Groceries',
    splits: parts,
    receiptScanId: 11,
    receiptImagePath: '/data/receipts/7.jpg',
    recurringRuleId: 4,
    isRecurring: true,
    createdAt: createdAt,
  );

  TransactionModel income() => TransactionModel(
    id: 8,
    accountId: 2,
    categoryId: 16,
    amountCents: 45000000,
    type: TransactionType.income,
    date: date,
    createdAt: createdAt,
  );

  TransactionModel transferHalf(TransferDirection direction) =>
      TransactionModel(
        id: direction == TransferDirection.out ? 9 : 10,
        accountId: direction == TransferDirection.out ? 1 : 2,
        amountCents: 500000,
        type: TransactionType.transfer,
        transferDirection: direction,
        date: date,
        note: 'To savings',
        createdAt: createdAt,
      );

  const splits = [
    TransactionSplit(id: 1, categoryId: 3, amountCents: 75000, note: 'Food'),
    TransactionSplit(id: 2, categoryId: 5, amountCents: 50000),
  ];

  /// Every shape a transaction can take, so the property tests below cover
  /// the matrix rather than one happy case.
  final cases = <String, TransactionModel>{
    'expense': expense(),
    'expense, unsaved (no id)': expense(id: null),
    'expense, split across two categories': expense(parts: splits),
    'income, minimal fields': income(),
    'transfer, debit half': transferHalf(TransferDirection.out),
    'transfer, credit half': transferHalf(TransferDirection.incoming),
  };

  group('round trip', () {
    // The property that matters: writing a transaction and reading it back
    // returns the same transaction. It catches a whole class of bug — a
    // forgotten column, a mismatched enum encoding, a boolean written as
    // `true` instead of 1 — generically, rather than one case at a time.
    for (final entry in cases.entries) {
      test('fromMap(toMap(x)) == x — ${entry.key}', () {
        final original = entry.value;
        final restored = TransactionModel.fromMap(
          original.toMap(now: now),
          splitRows: original.splitMaps(original.id ?? 99),
        );

        expect(restored, original);
      });
    }

    test('a split survives with its parts, ids and notes intact', () {
      final original = expense(parts: splits);
      final restored = TransactionModel.fromMap(
        original.toMap(now: now),
        splitRows: original.splitMaps(7),
      );

      expect(restored.splits, splits);
      expect(restored.splitTotalCents, 125000);
      expect(restored.dominantCategoryId, 3);
    });

    test('reading a split row without its parts yields a header', () {
      // A list view reads the parent alone (E-04). That is a legitimate read,
      // not an error, and it must not throw.
      final restored = TransactionModel.fromMap(
        expense(parts: splits).toMap(now: now),
      );

      expect(restored.splits, isEmpty);
      expect(restored.categoryId, 3);
    });
  });

  group('is_split', () {
    // The column is a denormalised copy of "are there child rows". If anything
    // could set it independently it would drift, and a transaction would claim
    // a breakdown that does not exist.
    for (final entry in cases.entries) {
      test('matches splits.isNotEmpty — ${entry.key}', () {
        final model = entry.value;
        expect(
          model.toMap(now: now)['is_split'],
          model.splits.isNotEmpty ? 1 : 0,
        );
      });
    }
  });

  group('columns match the schema', () {
    // Round-tripping through the model proves toMap and fromMap agree with
    // each other. It does not prove either agrees with the database — a
    // consistent typo in both round-trips perfectly and then fails on the
    // first INSERT. So compare against the real DDL.
    test('toMap writes exactly the columns transactions declares', () {
      expect(
        expense().toMap(now: now).keys.toSet(),
        _columnsOf('transactions'),
        reason:
            'a column on one side and not the other is either data the '
            'model silently drops on load, or an INSERT that will fail',
      );
    });

    test(
      'a split row writes exactly the columns transaction_splits declares',
      () {
        expect(
          TransactionSplitMapper.toMap(
            splits.first,
            transactionId: 7,
          ).keys.toSet(),
          _columnsOf('transaction_splits'),
        );
      },
    );

    test('an unsaved transaction omits id so SQLite assigns one', () {
      expect(expense(id: null).toMap(now: now).containsKey('id'), isFalse);
    });
  });

  group('transfer direction', () {
    test("encodes as 'out' and 'in', not the enum's own names", () {
      // TransferDirection.incoming.name is 'incoming'; the column's CHECK
      // accepts only 'in'. Using .name here would pass every unit test that
      // does not touch SQLite and fail on the first real insert.
      expect(
        transferHalf(TransferDirection.out)
            .toMap(now: now)['transfer_direction'],
        'out',
      );
      expect(
        transferHalf(TransferDirection.incoming)
            .toMap(now: now)['transfer_direction'],
        'in',
      );
      expect(TransferDirection.incoming.name, isNot('in'));
    });

    test('is null for everything that is not a transfer (E-16)', () {
      expect(expense().toMap(now: now)['transfer_direction'], isNull);
      expect(income().toMap(now: now)['transfer_direction'], isNull);
    });

    test('an unknown value from the database is rejected, not guessed', () {
      final map = expense().toMap(now: now)
        ..['type'] = 'transfer'
        ..['transfer_direction'] = 'sideways';

      expect(
        () => TransactionModel.fromMap(map),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('date encoding', () {
    test('stores the local calendar date, whatever the instant', () {
      // Asserted against the instant's own local fields rather than a literal,
      // so this holds on a developer machine in Colombo and on a CI runner in
      // UTC. The property is what matters: the date written is the date the
      // user would see on the wall.
      final instants = [
        DateTime(2026, 9, 2, 23, 30),
        DateTime(2026, 9, 2),
        DateTime.utc(2026, 9, 2, 18, 30),
        DateTime.utc(2026, 1, 1),
      ];

      for (final instant in instants) {
        final local = instant.toLocal();
        final month = local.month.toString().padLeft(2, '0');
        final day = local.day.toString().padLeft(2, '0');
        expect(
          TransactionModel.encodeDate(instant),
          '${local.year}-$month-$day',
          reason: '$instant should encode as its local calendar date',
        );
      }
    });

    test('a late-evening entry keeps its own day, not tomorrow', () {
      // The reason the local/UTC choice is not cosmetic. Serialising through
      // UTC would push anything after 18:30 in Colombo (UTC+5:30) onto the
      // next day, and FR-EXP-006's daily grouping, every date filter and the
      // Money Plan's month buckets would all inherit the shift.
      expect(
        TransactionModel.encodeDate(DateTime(2026, 9, 2, 23, 30)),
        '2026-09-02',
      );
      expect(
        TransactionModel.encodeDate(DateTime(2026, 12, 31, 23, 59)),
        '2026-12-31',
      );
    });

    test('pads single-digit months and days so the string sorts', () {
      // ISO-8601 as TEXT is only order-preserving when it is fixed width, and
      // every date-range index depends on that ordering.
      expect(TransactionModel.encodeDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('drops a time component rather than round-tripping it', () {
      final restored = TransactionModel.fromMap(
        expense().toMap(now: now)..['date'] = '2026-09-02',
      );

      expect(restored.date, DateTime(2026, 9, 2));
    });

    test('a malformed date is rejected, not guessed', () {
      final map = expense().toMap(now: now)..['date'] = '02/09/2026';

      expect(
        () => TransactionModel.fromMap(map),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('timestamps', () {
    test('created_at is stamped on the first write', () {
      final fresh = TransactionModel.fromEntity(expense().toEntity());

      expect(fresh.toMap(now: now)['created_at'], now.toIso8601String());
    });

    test('created_at is carried over on later writes', () {
      expect(
        expense().toMap(now: now)['created_at'],
        createdAt.toIso8601String(),
      );
    });

    test('updated_at is recomputed, never carried over', () {
      // The asymmetry that is easy to miss: created_at is preserved, so the
      // two look like they behave the same way. Reusing updated_at from
      // fromMap would leave every edited row claiming it had never changed.
      final loaded = TransactionModel.fromMap(expense().toMap(now: now));
      final later = DateTime(2026, 9, 5, 9);

      expect(loaded.updatedAt, now);
      expect(loaded.toMap(now: later)['updated_at'], later.toIso8601String());
      expect(
        loaded.toMap(now: later)['created_at'],
        createdAt.toIso8601String(),
      );
    });
  });

  group('booleans', () {
    test('is_recurring is written as 1 and 0, not true and false', () {
      expect(expense().toMap(now: now)['is_recurring'], 1);
      expect(income().toMap(now: now)['is_recurring'], 0);
    });

    test('reads back as a bool', () {
      expect(
        TransactionModel.fromMap(expense().toMap(now: now)).isRecurring,
        isTrue,
      );
      expect(
        TransactionModel.fromMap(income().toMap(now: now)).isRecurring,
        isFalse,
      );
    });
  });

  group('entity boundary', () {
    test('toEntity returns a plain Transaction with every field intact', () {
      final entity = expense(parts: splits).toEntity();

      expect(entity.runtimeType, Transaction);
      expect(entity.id, 7);
      expect(entity.categoryId, 3);
      expect(entity.amountCents, 125000);
      expect(entity.receiptScanId, 11);
      expect(entity.receiptImagePath, '/data/receipts/7.jpg');
      expect(entity.recurringRuleId, 4);
      expect(entity.isRecurring, isTrue);
      expect(entity.splits, splits);
    });

    test('a model never equals an identical entity', () {
      // Equatable compares runtimeType. Documented as a test because the
      // failure it produces otherwise — two objects that print identically and
      // compare unequal — is genuinely hard to read. The repository converts
      // with toEntity() at the boundary so callers never meet this.
      final model = expense();

      expect(model, isNot(model.toEntity()));
      expect(model.toEntity(), model.toEntity());
    });

    test('fromEntity then toEntity is the identity', () {
      final entity = expense(parts: splits).toEntity();

      expect(TransactionModel.fromEntity(entity).toEntity(), entity);
    });
  });

  group('unknown type', () {
    test('is rejected, not guessed', () {
      final map = expense().toMap(now: now)..['type'] = 'refund';

      expect(
        () => TransactionModel.fromMap(map),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

/// The column names [table] declares, read from the migration itself.
///
/// Parsed rather than hardcoded so that adding a column to the schema without
/// teaching the model about it fails a test, instead of failing at runtime on
/// a device.
Set<String> _columnsOf(String table) {
  final ddl = v1Statements.firstWhere(
    (s) => s.contains('CREATE TABLE $table ('),
    orElse: () => throw StateError('No CREATE TABLE for $table'),
  );

  final body = ddl.substring(ddl.indexOf('(') + 1, ddl.lastIndexOf(')'));
  final identifier = RegExp(r'^[a-z][a-z0-9_]*$');

  return body
      .split('\n')
      .map((line) => line.trim())
      // Constraint clauses, continuation lines and comments all start with
      // something that is not a lowercase identifier, which is what makes
      // "first token on the line" a sound rule here.
      .map((line) => line.split(RegExp(r'\s+')).first)
      .where(identifier.hasMatch)
      .toSet();
}
