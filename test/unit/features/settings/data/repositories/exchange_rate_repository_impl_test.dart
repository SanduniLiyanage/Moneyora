import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/settings/data/datasources/exchange_rate_local_datasource.dart';
import 'package:moneyora/features/settings/data/models/exchange_rate_model.dart';
import 'package:moneyora/features/settings/data/repositories/exchange_rate_repository_impl.dart';
import 'package:moneyora/features/settings/domain/entities/exchange_rate.dart';

/// Translation only: exceptions to failures, models to entities, and a
/// watch that follows writes and can be cancelled.
void main() {
  late _FakeLocalDataSource local;
  late ExchangeRateRepositoryImpl repository;

  final when = DateTime(2026, 9, 17);

  ExchangeRateModel model({int micros = 300000000}) => ExchangeRateModel(
    fromCurrency: 'USD',
    toCurrency: 'LKR',
    rateMicros: micros,
    updatedAt: when,
  );

  Future<void> settle() async {
    for (var turn = 0; turn < 5; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    local = _FakeLocalDataSource();
    repository = ExchangeRateRepositoryImpl(local);
  });

  tearDown(() => local.dispose());

  test('set writes a model built from the entity', () async {
    final result = await repository.set(model().toEntity());

    expect(result, const Right<Failure, Unit>(unit));
    expect(local.stored.single, isA<ExchangeRateModel>());
  });

  test('remove passes the pair through', () async {
    await repository.remove(fromCurrency: 'USD', toCurrency: 'LKR');

    expect(local.removed, [('USD', 'LKR')]);
  });

  test('a cache exception becomes a cache failure', () async {
    local.failWith = const CacheException('database is locked');

    expect(
      await repository.set(model().toEntity()),
      const Left<Failure, Unit>(CacheFailure('database is locked')),
    );
  });

  group('watch', () {
    test('hands up entities, and follows every write', () async {
      final seen = <Either<Failure, List<ExchangeRate>>>[];
      final sub = repository.watch().listen(seen.add);
      await settle();

      await repository.set(model().toEntity());
      await settle();

      expect(seen, hasLength(2));
      expect(seen.first.toNullable(), isEmpty);
      final last = seen.last.toNullable()!;
      expect(last, [model().toEntity()]);
      expect(last.single, isNot(isA<ExchangeRateModel>()));
      await sub.cancel();
    });

    test('stops listening to the datasource once cancelled', () async {
      final sub = repository.watch().listen((_) {});
      await settle();
      expect(local.listened, isTrue);

      await sub.cancel();
      await settle();

      expect(local.listened, isFalse);
    });
  });
}

class _FakeLocalDataSource implements ExchangeRateLocalDataSource {
  final List<ExchangeRateModel> stored = [];
  final List<(String, String)> removed = [];
  AppException? failWith;

  final _changes = StreamController<void>.broadcast();

  bool get listened => _changes.hasListener;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<ExchangeRateModel>> list() async {
    if (failWith case final e?) throw e;
    return List.of(stored);
  }

  @override
  Future<void> upsert(ExchangeRateModel rate) async {
    if (failWith case final e?) throw e;
    stored.add(rate);
    _changes.add(null);
  }

  @override
  Future<void> remove({
    required String fromCurrency,
    required String toCurrency,
  }) async {
    if (failWith case final e?) throw e;
    removed.add((fromCurrency, toCurrency));
    _changes.add(null);
  }

  @override
  Future<void> dispose() => _changes.close();
}
