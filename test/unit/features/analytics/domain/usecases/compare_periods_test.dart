import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/spending_query.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/compare_periods.dart';

const _food = CategoryTotal(
  categoryId: 1,
  name: 'Food',
  color: '#FF7043',
  amountCents: 100000,
);
const _transport = CategoryTotal(
  categoryId: 2,
  name: 'Transport',
  color: '#42A5F5',
  amountCents: 50000,
);

/// Returns canned totals for whichever range it is asked for, keyed by call
/// order, and can be told to fail on either call.
class _FakeRepository implements AnalyticsRepository {
  final List<DateRange> asked = [];
  Failure? failFirstWith;
  Failure? failSecondWith;
  List<List<CategoryTotal>> totals = const [[], []];

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    SpendingQuery query,
  ) async {
    asked.add(query.range);
    final failure = asked.length == 1 ? failFirstWith : failSecondWith;
    if (failure != null) return Left(failure);
    return Right(totals[asked.length - 1]);
  }

  @override
  Future<Either<Failure, int>> incomeForPeriod(DateRange range) =>
      throw UnimplementedError();
}

void main() {
  late _FakeRepository repository;
  late ComparePeriods comparePeriods;

  setUp(() {
    repository = _FakeRepository();
    comparePeriods = ComparePeriods(repository);
  });

  final july = DateRange(from: DateTime(2026, 7), to: DateTime(2026, 7, 31));
  final august = DateRange(from: DateTime(2026, 8), to: DateTime(2026, 8, 31));

  group('happy path', () {
    test('queries both periods through the repository, in order', () async {
      await comparePeriods(
        ComparePeriodsParams(periodA: july, periodB: august),
      );

      expect(repository.asked, [july, august]);
    });

    test(
      'a category spent in both periods gets the later minus the earlier',
      () async {
        repository.totals = [
          const [_food],
          [_food.copyWithAmount(150000)],
        ];

        final result = await comparePeriods(
          ComparePeriodsParams(periodA: july, periodB: august),
        );

        result.fold((f) => fail('unexpected failure: $f'), (deltas) {
          expect(deltas.single.categoryId, _food.categoryId);
          expect(deltas.single.deltaCents, 50000);
        });
      },
    );

    test(
      'a category dropped in the later period is a full negative delta',
      () async {
        repository.totals = [
          const [_food],
          const [],
        ];

        final result = await comparePeriods(
          ComparePeriodsParams(periodA: july, periodB: august),
        );

        result.fold((f) => fail('unexpected failure: $f'), (deltas) {
          expect(deltas.single.deltaCents, -100000);
        });
      },
    );

    test(
      'a category new in the later period is a full positive delta',
      () async {
        repository.totals = [
          const [],
          const [_food],
        ];

        final result = await comparePeriods(
          ComparePeriodsParams(periodA: july, periodB: august),
        );

        result.fold((f) => fail('unexpected failure: $f'), (deltas) {
          expect(deltas.single.deltaCents, 100000);
        });
      },
    );

    test('orders by the size of the movement, largest first', () async {
      repository.totals = [
        const [_food, _transport],
        [_food.copyWithAmount(110000), _transport.copyWithAmount(200000)],
      ];

      final result = await comparePeriods(
        ComparePeriodsParams(periodA: july, periodB: august),
      );

      result.fold((f) => fail('unexpected failure: $f'), (deltas) {
        expect(deltas.map((d) => d.name), ['Transport', 'Food']);
        expect(deltas.first.deltaCents, 150000);
        expect(deltas.last.deltaCents, 10000);
      });
    });

    test(
      'nothing spent in either period is an empty answer, not a failure',
      () async {
        final result = await comparePeriods(
          ComparePeriodsParams(periodA: july, periodB: august),
        );

        result.fold(
          (f) => fail('unexpected failure: $f'),
          (deltas) => expect(deltas, isEmpty),
        );
      },
    );

    test('passes a failure from the first period through, without querying the second', () async {
      repository.failFirstWith = const CacheFailure('database is locked');

      final result = await comparePeriods(
        ComparePeriodsParams(periodA: july, periodB: august),
      );

      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('should not have returned deltas'),
      );
      expect(repository.asked, [july]);
    });

    test('passes a failure from the second period through', () async {
      repository.failSecondWith = const CacheFailure('database is locked');

      final result = await comparePeriods(
        ComparePeriodsParams(periodA: july, periodB: august),
      );

      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('should not have returned deltas'),
      );
    });
  });

  group('validation', () {
    test('rejects an inverted period A, without querying', () async {
      final result = await comparePeriods(
        ComparePeriodsParams(
          periodA: DateRange(
            from: DateTime(2026, 7, 31),
            to: DateTime(2026, 7),
          ),
          periodB: august,
        ),
      );

      result.fold((failure) {
        expect(failure, isA<ValidationFailure>());
        expect((failure as ValidationFailure).field, 'periodA');
      }, (_) => fail('should not have returned deltas'));
      expect(repository.asked, isEmpty);
    });

    test('rejects an inverted period B, without querying', () async {
      final result = await comparePeriods(
        ComparePeriodsParams(
          periodA: july,
          periodB: DateRange(
            from: DateTime(2026, 8, 31),
            to: DateTime(2026, 8),
          ),
        ),
      );

      result.fold((failure) {
        expect(failure, isA<ValidationFailure>());
        expect((failure as ValidationFailure).field, 'periodB');
      }, (_) => fail('should not have returned deltas'));
      expect(repository.asked, isEmpty);
    });
  });
}

extension on CategoryTotal {
  CategoryTotal copyWithAmount(int amountCents) => CategoryTotal(
    categoryId: categoryId,
    name: name,
    color: color,
    amountCents: amountCents,
  );
}
