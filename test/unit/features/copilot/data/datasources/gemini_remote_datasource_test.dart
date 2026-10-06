import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/copilot/data/datasources/gemini_remote_datasource.dart';
import 'package:moneyora/features/copilot/data/datasources/secure_llm_api_key_store.dart';
import 'package:moneyora/features/copilot/domain/entities/agent_tool.dart';
import 'package:moneyora/features/copilot/domain/entities/llm_step.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_call.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_exchange.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_result.dart';

/// The datasource against a mocked transport.
///
/// Nothing here reaches the network. What is being tested is the part that can
/// be got wrong silently: which header the key travels in, what a 429 becomes,
/// and whether a reply in an unexpected shape throws something the repository
/// above knows how to convert.
void main() {
  const tools = [
    AgentTool(
      name: 'get_spending_by_category',
      description: 'totals per category',
      parameters: {'type': 'object'},
    ),
  ];

  /// A minimal well-formed reply carrying a final answer.
  String answerBody(String text) => jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  });

  /// A reply asking for one tool.
  String callBody(String name, Map<String, dynamic> args) => jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {
              'functionCall': {'name': name, 'args': args},
            },
          ],
        },
      },
    ],
  });

  GeminiRemoteDataSource sourceReturning(
    http.Response Function(http.Request request) respond, {
    String? apiKey = 'test-key',
  }) => GeminiRemoteDataSource(
    MockClient((request) async => respond(request)),
    InMemoryLlmApiKeyStore(apiKey),
  );

  Future<LlmStep> ask(GeminiRemoteDataSource source) => source.reason(
    question: 'How much did I spend on food in August?',
    tools: tools,
    history: const [],
  );

  group('the request', () {
    test('carries the key in a header, never in the URL', () async {
      // A URL is logged by proxies, crash reporters and `flutter run`. A
      // header is not. This is the difference between a key that is secret and
      // one that is merely not printed on purpose.
      late http.Request seen;
      final source = sourceReturning((request) {
        seen = request;
        return http.Response(answerBody('ok'), 200);
      });

      await ask(source);

      expect(seen.headers['x-goog-api-key'], 'test-key');
      expect(seen.url.query, isEmpty);
      expect(seen.url.toString(), isNot(contains('test-key')));
    });

    test('posts to the configured model over https', () async {
      late http.Request seen;
      final source = sourceReturning((request) {
        seen = request;
        return http.Response(answerBody('ok'), 200);
      });

      await ask(source);

      expect(seen.method, 'POST');
      expect(seen.url.scheme, 'https');
      expect(seen.url.path, contains(GeminiRemoteDataSource.defaultModel));
      expect(seen.url.path, endsWith(':generateContent'));
    });

    test('tells the model what day it is', () async {
      // "Last month" means nothing to a model that does not know the date;
      // it guesses one from its training, and the totals come back empty.
      late http.Request seen;
      final source = GeminiRemoteDataSource(
        MockClient((request) async {
          seen = request;
          return http.Response(answerBody('ok'), 200);
        }),
        InMemoryLlmApiKeyStore('test-key'),
        clock: () => DateTime(2026, 10, 6, 21, 30),
      );

      await ask(source);

      final instruction =
          (((jsonDecode(seen.body) as Map)['system_instruction']
                          as Map)['parts']
                      as List)
                  .single
              as Map;
      expect(instruction['text'], endsWith('Today is 2026-10-06.'));
    });

    test('asks the current Flash model by its alias, not a dated name', () {
      // 1.0.1 asked `gemini-2.0-flash`, which Google shut down on 2026-06-01:
      // every question failed. The alias follows each new Flash release.
      expect(GeminiRemoteDataSource.defaultModel, 'gemini-flash-latest');
    });

    test('a model that is gone falls back to the pinned stable one', () async {
      final asked = <String>[];
      final source = sourceReturning((request) {
        asked.add(request.url.path);
        return asked.length == 1
            ? http.Response('{"error":{"code":404,"status":"NOT_FOUND"}}', 404)
            : http.Response(answerBody('ok'), 200);
      });

      final step = await ask(source);

      expect((step as FinalAnswer).text, 'ok');
      expect(asked, hasLength(2));
      expect(asked.first, contains(GeminiRemoteDataSource.defaultModel));
      expect(asked.last, contains(GeminiRemoteDataSource.fallbackModel));
    });

    test('replays each turn together: its calls with their signatures and '
        'ids, then their results from the user', () async {
      // Gemini 3 refuses a function call replayed without the
      // thoughtSignature it came with (a 400), and expects a turn's calls
      // in one model turn, answered in one user turn.
      late http.Request seen;
      final source = sourceReturning((request) {
        seen = request;
        return http.Response(answerBody('ok'), 200);
      });

      await source.reason(
        question: 'Food in August and July?',
        tools: tools,
        history: const [
          ToolExchange(
            call: ToolCall(
              toolName: 'get_spending_by_category',
              args: {'from': '2026-08-01', 'to': '2026-08-31'},
              id: 'call-1',
              signature: 'sig-A',
            ),
            result: ToolResult(
              toolName: 'get_spending_by_category',
              aggregate: {
                'totals_cents': {'Food': 3420000},
              },
            ),
          ),
          ToolExchange(
            call: ToolCall(
              toolName: 'get_spending_by_category',
              args: {'from': '2026-07-01', 'to': '2026-07-31'},
              id: 'call-2',
            ),
            result: ToolResult(
              toolName: 'get_spending_by_category',
              aggregate: {
                'totals_cents': {'Food': 2900000},
              },
            ),
          ),
        ],
      );

      final contents =
          (jsonDecode(seen.body) as Map<String, dynamic>)['contents']! as List;
      expect(contents.map((c) => (c as Map)['role']), [
        'user',
        'model',
        'user',
      ]);

      final calls = (contents[1] as Map)['parts'] as List;
      expect(calls, hasLength(2));
      expect((calls[0] as Map)['thoughtSignature'], 'sig-A');
      expect(((calls[0] as Map)['functionCall'] as Map)['id'], 'call-1');
      expect((calls[1] as Map).containsKey('thoughtSignature'), isFalse);

      final results = (contents[2] as Map)['parts'] as List;
      expect(results, hasLength(2));
      expect(((results[1] as Map)['functionResponse'] as Map)['id'], 'call-2');
    });

    test('a later turn is replayed as a turn of its own', () async {
      late http.Request seen;
      final source = sourceReturning((request) {
        seen = request;
        return http.Response(answerBody('ok'), 200);
      });

      await source.reason(
        question: 'q',
        tools: tools,
        history: const [
          ToolExchange(
            call: ToolCall(toolName: 'a', args: {}),
            result: ToolResult(toolName: 'a', aggregate: {}),
          ),
          ToolExchange(
            call: ToolCall(toolName: 'b', args: {}),
            result: ToolResult(toolName: 'b', aggregate: {}),
            turn: 1,
          ),
        ],
      );

      final contents =
          (jsonDecode(seen.body) as Map<String, dynamic>)['contents']! as List;
      expect(contents.map((c) => (c as Map)['role']), [
        'user',
        'model',
        'user',
        'model',
        'user',
      ]);
    });
  });

  group('reading the reply', () {
    test('a text part is the final answer', () async {
      final source = sourceReturning(
        (_) => http.Response(answerBody('You spent 34,200 on food.'), 200),
      );

      final step = await ask(source);

      expect(step, isA<FinalAnswer>());
      expect((step as FinalAnswer).text, 'You spent 34,200 on food.');
    });

    test('a function call is a tool request, with its arguments', () async {
      final source = sourceReturning(
        (_) => http.Response(
          callBody('get_spending_by_category', {
            'from': '2026-08-01',
            'to': '2026-08-31',
          }),
          200,
        ),
      );

      final step = await ask(source);

      expect(step, isA<ToolCallsRequested>());
      final call = (step as ToolCallsRequested).calls.single;
      expect(call.toolName, 'get_spending_by_category');
      expect(call.args, {'from': '2026-08-01', 'to': '2026-08-31'});
    });

    test('a call wins over text in the same reply', () async {
      // A model that thinks aloud on its way to a call would otherwise end the
      // loop one step early, with its own musing as the answer.
      final source = sourceReturning(
        (_) => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Let me look that up.'},
                    {
                      'functionCall': {
                        'name': 'get_spending_by_category',
                        'args': <String, dynamic>{},
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        ),
      );

      expect(await ask(source), isA<ToolCallsRequested>());
    });

    test('several calls in one reply all come through', () async {
      final source = sourceReturning(
        (_) => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'functionCall': {
                        'name': 'a',
                        'args': <String, dynamic>{},
                      },
                    },
                    {
                      'functionCall': {
                        'name': 'b',
                        'args': <String, dynamic>{},
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        ),
      );

      final step = await ask(source);

      expect((step as ToolCallsRequested).calls.map((c) => c.toolName), [
        'a',
        'b',
      ]);
    });

    test('a call keeps the signature and id it came with', () async {
      final source = sourceReturning(
        (_) => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'functionCall': {
                        'id': 'call-1',
                        'name': 'get_spending_by_category',
                        'args': <String, dynamic>{},
                      },
                      'thoughtSignature': 'sig-A',
                    },
                  ],
                },
              },
            ],
          }),
          200,
        ),
      );

      final call = ((await ask(source)) as ToolCallsRequested).calls.single;

      expect(call.id, 'call-1');
      expect(call.signature, 'sig-A');
    });
  });

  group('what can go wrong', () {
    test('no key at all is a failure the user can act on', () async {
      // Not a crash on first launch. Nobody has set a key yet, and the message
      // has to say where to put one.
      final source = sourceReturning(
        (_) => http.Response(answerBody('ok'), 200),
        apiKey: null,
      );

      // It says where the key goes: on the Ask Moneyora screen. It said
      // Settings, where there is no such field.
      await expectLater(
        ask(source),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Ask Moneyora'), isNot(contains('Settings'))),
          ),
        ),
      );
    });

    test(
      'a key Google calls invalid is a rejected key, though it is a 400',
      () async {
        // Gemini answers a mistyped key with 400 INVALID_ARGUMENT, reason
        // API_KEY_INVALID, not 401 — which read as "could not answer that".
        final source = sourceReturning(
          (_) => http.Response(
            jsonEncode({
              'error': {
                'code': 400,
                'message': 'API key not valid. Please pass a valid API key.',
                'status': 'INVALID_ARGUMENT',
                'details': [
                  {
                    '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
                    'reason': 'API_KEY_INVALID',
                  },
                ],
              },
            }),
            400,
          ),
        );

        await expectLater(
          ask(source),
          throwsA(
            isA<ServerException>()
                .having((e) => e.message, 'message', contains('key'))
                .having(
                  (e) => e.message,
                  'message',
                  isNot(contains('Settings')),
                ),
          ),
        );
      },
    );

    test('a spent quota keeps its 429, so it can be told apart', () async {
      // The repository needs the code: waiting fixes a 429 and fixes nothing
      // else, so it is the one status with different advice attached.
      final source = sourceReturning((_) => http.Response('{}', 429));

      await expectLater(
        ask(source),
        throwsA(
          isA<ServerException>().having((e) => e.statusCode, 'status', 429),
        ),
      );
    });

    test('a rejected key says so plainly', () async {
      final source = sourceReturning((_) => http.Response('{}', 403));

      await expectLater(
        ask(source),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            contains('key'),
          ),
        ),
      );
    });

    test('a server error is a server error', () async {
      final source = sourceReturning((_) => http.Response('{}', 503));

      await expectLater(
        ask(source),
        throwsA(
          isA<ServerException>().having((e) => e.statusCode, 'status', 503),
        ),
      );
    });

    test('a transport failure does not escape as itself', () async {
      // Nothing above data/ has a try/catch, so an http exception reaching the
      // repository would reach a widget.
      final source = sourceReturning((_) => throw const SocketLikeException());

      await expectLater(ask(source), throwsA(isA<ServerException>()));
    });

    test('a body that is not JSON at all', () async {
      final source = sourceReturning(
        (_) => http.Response('<html>502 Bad Gateway</html>', 200),
      );

      await expectLater(ask(source), throwsA(isA<ServerException>()));
    });

    test('a 200 with no candidates — a safety block looks like this', () async {
      final source = sourceReturning(
        (_) => http.Response(jsonEncode({'candidates': <dynamic>[]}), 200),
      );

      await expectLater(ask(source), throwsA(isA<ServerException>()));
    });

    test('a reply with neither an answer nor a call', () async {
      final source = sourceReturning(
        (_) => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {'parts': <dynamic>[]},
              },
            ],
          }),
          200,
        ),
      );

      await expectLater(ask(source), throwsA(isA<ServerException>()));
    });
  });

  group('the key store', () {
    test('holds, replaces and clears a key', () async {
      final store = InMemoryLlmApiKeyStore();
      expect(await store.read(), isNull);

      await store.write('  a-key  ');
      // Trimmed: a key pasted from a browser arrives with whitespace, and a
      // trailing newline in a header is a rejected request with no clue why.
      expect(await store.read(), 'a-key');

      await store.clear();
      expect(await store.read(), isNull);
    });
  });
}

/// Stands in for a transport error without depending on `dart:io`.
class SocketLikeException implements Exception {
  const SocketLikeException();
}
