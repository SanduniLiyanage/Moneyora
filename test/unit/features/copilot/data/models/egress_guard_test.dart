import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/copilot/data/models/llm_dtos.dart';
import 'package:moneyora/features/copilot/domain/entities/agent_tool.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_call.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_exchange.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_result.dart';

/// THE PRIVACY GUARD (FR-COP-011, NFR-PRI-003).
///
/// Moneyora's promise is that financial data stays on the phone. The Copilot
/// is the one feature that sends anything at all, so this test builds a real
/// outbound request and asserts what is in it.
///
/// **If this ever fails, something is putting raw records on the wire.** That
/// is a privacy regression, not a test to relax.
void main() {
  const tools = [
    AgentTool(
      name: 'get_spending_by_category',
      description: 'Returns the total spent per category, in integer cents.',
      parameters: {
        'type': 'object',
        'properties': {
          'from': {'type': 'string'},
          'to': {'type': 'string'},
        },
      },
    ),
  ];

  final history = [
    const ToolExchange(
      call: ToolCall(
        toolName: 'get_spending_by_category',
        args: {'from': '2026-08-01', 'to': '2026-08-31'},
      ),
      result: ToolResult(
        toolName: 'get_spending_by_category',
        aggregate: {
          'from': '2026-08-01',
          'to': '2026-08-31',
          'totals_cents': {'Food': 3420000, 'Transport': 900000},
        },
      ),
    ),
  ];

  String serialise({String question = 'Where did my budget slip in August?'}) =>
      jsonEncode(
        GeminiDtos.buildRequestBody(
          question: question,
          tools: tools,
          history: history,
        ),
      );

  group('what may never appear in an outbound request', () {
    // Column names from the schema, plus the words a leak would carry. Each is
    // checked against the serialised body, so a nested field is caught as
    // surely as a top-level one.
    const forbidden = <String>[
      'transaction_id',
      'account_id',
      'category_id',
      'merchant',
      'receipt',
      'receipt_image_path',
      'amount_cents',
      'created_at',
      'updated_at',
      'transfer_direction',
      'passcode',
      'api_key',
    ];

    for (final field in forbidden) {
      test('no "$field"', () {
        expect(
          serialise().toLowerCase(),
          isNot(contains(field)),
          reason: 'a raw field reached the outbound payload',
        );
      });
    }

    test('no free-text note the user typed', () {
      // Notes are the field most likely to hold something private — a name, a
      // reason, a diagnosis. They are never aggregated, so they can only get
      // out by accident.
      expect(serialise().toLowerCase(), isNot(contains('"note"')));
    });
  });

  group('what the request does carry', () {
    test('the question, because that is what was asked', () {
      expect(serialise(), contains('Where did my budget slip in August?'));
    });

    test('the aggregate, because that is the answer', () {
      final body = serialise();
      expect(body, contains('totals_cents'));
      expect(body, contains('3420000'));
    });

    test('the tool schemas, so the model knows what it may call', () {
      expect(serialise(), contains('get_spending_by_category'));
    });

    test('an instruction never to guess a number', () {
      expect(GeminiDtos.systemInstruction.toLowerCase(), contains('never'));
      expect(GeminiDtos.systemInstruction.toLowerCase(), contains('tool'));
    });
  });

  group('the shape the API expects', () {
    test('the question is the first turn', () {
      final body = GeminiDtos.buildRequestBody(
        question: 'How much did I spend on food in August?',
        tools: tools,
        history: const [],
      );
      final contents = body['contents']! as List;

      expect(contents, hasLength(1));
      expect((contents.first as Map)['role'], 'user');
    });

    test('every tool result follows the call it answers', () {
      // A functionResponse without its functionCall is a reply to a question
      // the transcript does not contain, and providers reject it.
      final body = GeminiDtos.buildRequestBody(
        question: 'anything',
        tools: tools,
        history: history,
      );
      final contents = body['contents']! as List;

      expect(contents.map((c) => (c as Map)['role']), [
        'user',
        'model',
        'function',
      ]);
    });

    test('the model turn repeats the arguments the model chose', () {
      final body = GeminiDtos.buildRequestBody(
        question: 'anything',
        tools: tools,
        history: history,
      );
      final modelTurn = (body['contents']! as List)[1] as Map;
      final parts = modelTurn['parts']! as List;
      final call = (parts.single as Map)['functionCall']! as Map;

      expect(call['name'], 'get_spending_by_category');
      expect(call['args'], {'from': '2026-08-01', 'to': '2026-08-31'});
    });

    test('the tools are declared where the API looks for them', () {
      final body = GeminiDtos.buildRequestBody(
        question: 'anything',
        tools: tools,
        history: const [],
      );
      final declarations =
          ((body['tools']! as List).single as Map)['function_declarations']!
              as List;

      expect((declarations.single as Map)['name'], 'get_spending_by_category');
      expect(
        (declarations.single as Map)['parameters'],
        isA<Map<String, dynamic>>(),
      );
    });

    test('the whole body survives a JSON round trip', () {
      // It is encoded before it is sent; a value jsonEncode cannot handle
      // would throw at the moment of the request and nowhere earlier.
      expect(() => jsonDecode(serialise()), returnsNormally);
    });
  });
}
