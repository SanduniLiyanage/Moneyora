import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/spending_query.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_income_for_period.dart';

/// Records the range it was asked for, and can be told to fail.
class _FakeRepository implements AnalyticsRepository {
  DateRange? asked;
  Failure? failWith;
  int income = 9000000;

  @override
  Future<Either<Failure, int>> incomeForPeriod(DateRange range) async {
    asked = range;
    if (failWith case final failure?) return Left(failure);
    return Right(income);
  }

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    SpendingQuery query,
  ) => throw UnimplementedError();
}

void main() {
  late _FakeRepository repository;
  late GetIncomeForPeriod getIncomeForPeriod;

  setUp(() {
    repository = _FakeRepository();
    getIncomeForPeriod = GetIncomeForPeriod(repository);
  });

  final august = DateRange(from: DateTime(2026, 8), to: DateTime(2026, 8, 31));

  group('happy path', () {
    test('returns what the repository read, unchanged', () async {
      final result = await getIncomeForPeriod(august);

      result.fold(
        (f) => fail('unexpected failure: $f'),
        (income) => expect(income, 9000000),
      );
    });

    test('passes the range down untouched', () async {
      await getIncomeForPeriod(august);

      expect(repository.asked, august);
    });

    test('a period with no income is zero, not a failure', () async {
      repository.income = 0;

      final result = await getIncomeForPeriod(august);

      result.fold(
        (f) => fail('unexpected failure: $f'),
        (income) => expect(income, 0),
      );
    });

    test('passes a repository failure through unchanged', () async {
      repository.failWith = const CacheFailure('database is locked');

      final result = await getIncomeForPeriod(august);

      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('should not have returned an amount'),
      );
    });
  });

  group('validation', () {
    test('rejects a range that runs backwards, without querying', () async {
      final result = await getIncomeForPeriod(
        DateRange(from: DateTime(2026, 8, 31), to: DateTime(2026, 8)),
      );

      result.fold(
        (failure) => expect(failure, isA<ValidationFailure>()),
        (_) => fail('should not have returned an amount'),
      );
      expect(repository.asked, isNull);
    });

    test('accepts a single day', () async {
      final oneDay = DateRange(
        from: DateTime(2026, 8, 3),
        to: DateTime(2026, 8, 3),
      );

      expect(GetIncomeForPeriod.validate(oneDay), isNull);

      final result = await getIncomeForPeriod(oneDay);
      expect(result.isRight(), isTrue);
    });

    test('names the field at fault so a picker can highlight it', () {
      final failure = GetIncomeForPeriod.validate(
        DateRange(from: DateTime(2026, 9), to: DateTime(2026, 8)),
      );

      expect(failure?.field, 'from');
    });
  });
}
