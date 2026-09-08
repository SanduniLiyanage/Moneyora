/// The wire format for Gemini's `generateContent`, and the single point at
/// which anything leaves this device.
///
/// ## This file is the privacy boundary (SDD §7)
///
/// [GeminiDtos.buildRequestBody] is the only code that composes an outbound
/// payload, and it accepts exactly three things: the user's question, the tool
/// *schemas*, and the aggregate maps from [ToolResult]. It cannot be handed a
/// transaction, because it has no parameter that would take one.
///
/// That is a design that makes the leak hard rather than one that makes it
/// forbidden, so it is checked as well: `egress_guard_test.dart` serialises a
/// real request and fails if any raw-row field appears in it (FR-COP-011).
library;

import '../../domain/entities/agent_tool.dart';
import '../../domain/entities/llm_step.dart';
import '../../domain/entities/tool_call.dart';
import '../../domain/entities/tool_exchange.dart';

/// Builds and parses Gemini request and response bodies.
class GeminiDtos {
  const GeminiDtos._();

  /// What the model is told about its job, once per request.
  ///
  /// Three instructions earn their place. **Prefer tools over guessing**,
  /// because a plausible invented number is worse than no answer when the
  /// subject is someone's rent. **Money is integer cents**, because a model
  /// shown `3420000` will otherwise report thirty-four million. **Name the
  /// period and the category**, because NFR-USA-005 asks for an answer a
  /// person can check rather than a bare figure.
  static const String systemInstruction =
      'You are Moneyora, a personal finance assistant. Answer the user\'s '
      'question about their own money.\n'
      '\n'
      'Call a tool for every number you need. Never invent or estimate a '
      'figure — if no tool can supply it, say so plainly.\n'
      '\n'
      'All amounts are integer cents: divide by 100 before stating any amount, '
      'and write it in the local currency style.\n'
      '\n'
      'Answer in two or three sentences. Always say which period and which '
      'category a number refers to. You receive only totals, never individual '
      'transactions, and you must never ask for individual transactions.';

  /// Composes the outbound request.
  ///
  /// [history] is replayed as the conversation it was: each of the model's own
  /// calls, then the aggregate it received. A `functionResponse` sent without
  /// the `functionCall` it answers is a reply to a question the transcript
  /// never contains.
  static Map<String, dynamic> buildRequestBody({
    required String question,
    required List<AgentTool> tools,
    required List<ToolExchange> history,
  }) {
    final contents = <Map<String, dynamic>>[
      {
        'role': 'user',
        'parts': [
          {'text': question},
        ],
      },
    ];

    for (final exchange in history) {
      contents.add({
        'role': 'model',
        'parts': [
          {
            'functionCall': {
              'name': exchange.call.toolName,
              'args': exchange.call.args,
            },
          },
        ],
      });
      contents.add({
        'role': 'function',
        'parts': [
          {
            'functionResponse': {
              'name': exchange.result.toolName,
              // Aggregate-only by contract, and by the test that guards it.
              'response': exchange.result.aggregate,
            },
          },
        ],
      });
    }

    return {
      'system_instruction': {
        'parts': [
          {'text': systemInstruction},
        ],
      },
      'contents': contents,
      'tools': [
        {
          'function_declarations': [
            for (final tool in tools)
              {
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.parameters,
              },
          ],
        },
      ],
    };
  }

  /// Reads one turn of the model's reply.
  ///
  /// Returns [ToolCallsRequested] when the model asked for anything at all,
  /// and [FinalAnswer] otherwise. Calls win over text because a reply that
  /// carries both is a model thinking aloud on its way to a call, and treating
  /// that as the answer ends the loop one step early.
  ///
  /// Throws [FormatException] when the shape is unreadable; the datasource
  /// turns that into a failure. Nothing here trusts a field to exist.
  static LlmStep parseResponse(Map<String, dynamic> json) {
    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      // Also the shape of a safety block or a prompt rejection, both of which
      // arrive as a 200 with no candidate rather than as an error.
      throw const FormatException('The reply contained no answer.');
    }

    final first = candidates.first;
    final content = first is Map ? first['content'] : null;
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) {
      throw const FormatException('The reply contained no content.');
    }

    final calls = <ToolCall>[];
    final text = StringBuffer();

    for (final part in parts) {
      if (part is! Map) continue;

      final call = part['functionCall'];
      if (call is Map) {
        final name = call['name'];
        if (name is! String || name.isEmpty) continue;
        final args = call['args'];
        calls.add(
          ToolCall(
            toolName: name,
            args: args is Map
                ? args.map((key, value) => MapEntry('$key', value))
                : const {},
          ),
        );
        continue;
      }

      final chunk = part['text'];
      if (chunk is String) text.write(chunk);
    }

    if (calls.isNotEmpty) return ToolCallsRequested(calls);

    final answer = text.toString().trim();
    if (answer.isNotEmpty) return FinalAnswer(answer);

    throw const FormatException('The reply held neither an answer nor a call.');
  }
}
