import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/copilot/data/datasources/gemini_remote_datasource.dart';
import 'package:moneyora/features/copilot/data/datasources/secure_llm_api_key_store.dart';
import 'package:moneyora/features/copilot/data/repositories/llm_repository_impl.dart';
import 'package:moneyora/features/copilot/domain/entities/agent_tool.dart';
import 'package:moneyora/features/copilot/domain/entities/llm_step.dart';

/// The layer boundary: every way the model can fail, seen as a [Failure].
///
/// The distinctions matter because the screen says something different for
/// each. "You are offline", "the assistant is down" and "you have used up
/// today's quota" ask the user for three different things, and a repository
/// that flattens them costs the interface that difference.
void main() {
  const tools = [
    AgentTool(
      name: 'get_spending_by_category',
      description: 'totals per category',
      parameters: {'type': 'object'},
    ),
  ];

  LlmRepositoryImpl repositoryReturning(http.Response response) =>
      LlmRepositoryImpl(
        GeminiRemoteDataSource(
          MockClient((_) async => response),
          InMemoryLlmApiKeyStore('test-key'),
        ),
      );

  Future<Either<Failure, LlmStep>> ask(LlmRepositoryImpl repository) =>
      repository.reason(question: 'anything', tools: tools, history: const []);

  test('a good reply comes back as a step, not an exception', () async {
    final repository = repositoryReturning(
      http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'You spent 34,200 on food in August.'},
                ],
              },
            },
          ],
        }),
        200,
      ),
    );

    final result = await ask(repository);

    result.fold((f) => fail('unexpected failure: $f'), (step) {
      expect(step, isA<FinalAnswer>());
    });
  });

  test('a spent quota is its own failure, because waiting fixes it', () async {
    final repository = repositoryReturning(http.Response('{}', 429));

    final result = await ask(repository);

    result.fold((failure) {
      expect(failure, isA<QuotaFailure>());
      expect(failure.message.toLowerCase(), contains('quota'));
    }, (_) => fail('should not have answered'));
  });

  test('every other server error is a ServerFailure', () async {
    for (final status in [400, 403, 500, 503]) {
      final result = await ask(
        repositoryReturning(http.Response('{}', status)),
      );

      result.fold(
        (failure) =>
            expect(failure, isA<ServerFailure>(), reason: 'status $status'),
        (_) => fail('should not have answered'),
      );
    }
  });

  test('an unreadable reply fails rather than inventing a step', () async {
    // The alternative is worse than an error: a half-parsed reply would end
    // the loop with whatever fell out of it, presented as an answer.
    final repository = repositoryReturning(http.Response('not json', 200));

    final result = await ask(repository);

    expect(result.isLeft(), isTrue);
  });

  test('nothing throws out of the repository', () async {
    // The convention the whole app rests on: data/ throws, repositories
    // convert, and no layer above this one has a try/catch to catch anything.
    final repository = LlmRepositoryImpl(
      GeminiRemoteDataSource(
        MockClient((_) async => throw Exception('the network is on fire')),
        InMemoryLlmApiKeyStore('test-key'),
      ),
    );

    await expectLater(ask(repository), completes);
    expect((await ask(repository)).isLeft(), isTrue);
  });

  test('a missing key is a failure, not a crash on first launch', () async {
    final repository = LlmRepositoryImpl(
      GeminiRemoteDataSource(
        MockClient((_) async => http.Response('{}', 200)),
        InMemoryLlmApiKeyStore(),
      ),
    );

    final result = await ask(repository);

    result.fold(
      (failure) => expect(failure, isA<ServerFailure>()),
      (_) => fail('should not have answered'),
    );
  });
}
