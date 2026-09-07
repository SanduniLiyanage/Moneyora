import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/copilot/domain/entities/agent_tool.dart';
import 'package:moneyora/features/copilot/domain/entities/copilot_answer.dart';
import 'package:moneyora/features/copilot/domain/entities/llm_step.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_call.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_result.dart';

/// Equality is not decoration here. The loop compares steps and results, the
/// provider hands answers to Riverpod, and tests script a model turn by turn —
/// all of which quietly stop working when a `props` list omits a field. Every
/// entity is therefore walked field by field rather than spot-checked.
void main() {
  group('AgentTool', () {
    AgentTool tool() => const AgentTool(
      name: 'get_spending_by_category',
      description: 'totals per category',
      parameters: {'type': 'object'},
    );

    test('two identical declarations are equal', () {
      expect(tool(), tool());
      expect(tool().hashCode, tool().hashCode);
    });

    test('a difference in any field breaks equality', () {
      final variants = <String, AgentTool>{
        'name': const AgentTool(
          name: 'get_income_for_period',
          description: 'totals per category',
          parameters: {'type': 'object'},
        ),
        'description': const AgentTool(
          name: 'get_spending_by_category',
          description: 'income for a month',
          parameters: {'type': 'object'},
        ),
        'parameters': const AgentTool(
          name: 'get_spending_by_category',
          description: 'totals per category',
          parameters: {'type': 'string'},
        ),
      };

      variants.forEach((field, variant) {
        expect(variant, isNot(tool()), reason: '$field is missing from props');
      });
    });
  });

  group('ToolCall', () {
    test('equality covers the name and the arguments', () {
      const call = ToolCall(
        toolName: 'get_spending_by_category',
        args: {'from': '2026-08-01'},
      );

      expect(
        call,
        const ToolCall(
          toolName: 'get_spending_by_category',
          args: {'from': '2026-08-01'},
        ),
      );
      expect(
        call,
        isNot(
          const ToolCall(
            toolName: 'get_spending_by_category',
            args: {'from': '2026-07-01'},
          ),
        ),
      );
      expect(
        call,
        isNot(const ToolCall(toolName: 'get_income_for_period', args: {})),
      );
    });
  });

  group('ToolResult', () {
    test('equality reaches inside the aggregate map', () {
      // A shallow comparison would call two results equal while their totals
      // differ, which in a loop means a second identical-looking round trip is
      // treated as progress.
      const result = ToolResult(
        toolName: 'get_spending_by_category',
        aggregate: {
          'totals_cents': {'Food': 3420000},
        },
      );

      expect(
        result,
        const ToolResult(
          toolName: 'get_spending_by_category',
          aggregate: {
            'totals_cents': {'Food': 3420000},
          },
        ),
      );
      expect(
        result,
        isNot(
          const ToolResult(
            toolName: 'get_spending_by_category',
            aggregate: {
              'totals_cents': {'Food': 1},
            },
          ),
        ),
      );
    });
  });

  group('LlmStep', () {
    test('a final answer and a tool request are never equal', () {
      // Both are steps; confusing one for the other would either end the loop
      // early or run it forever.
      const answer = FinalAnswer('You spent 34,200 on food in August.');
      const request = ToolCallsRequested([
        ToolCall(toolName: 'get_spending_by_category', args: {}),
      ]);

      expect(answer, isNot(request));
    });

    test('answers compare by text', () {
      expect(const FinalAnswer('yes'), const FinalAnswer('yes'));
      expect(const FinalAnswer('yes'), isNot(const FinalAnswer('no')));
    });

    test('requests compare by the calls they carry', () {
      const one = ToolCallsRequested([
        ToolCall(toolName: 'get_spending_by_category', args: {}),
      ]);

      expect(
        one,
        const ToolCallsRequested([
          ToolCall(toolName: 'get_spending_by_category', args: {}),
        ]),
      );
      expect(one, isNot(const ToolCallsRequested([])));
    });
  });

  group('CopilotAnswer', () {
    test('equality covers the text and the trace', () {
      // The trace is shown to the user (FR-COP-003), so a change to it is a
      // change to the screen and must rebuild it.
      const answer = CopilotAnswer(
        text: 'You spent 34,200 on food in August.',
        trace: [ToolCall(toolName: 'get_spending_by_category', args: {})],
      );

      expect(
        answer,
        const CopilotAnswer(
          text: 'You spent 34,200 on food in August.',
          trace: [ToolCall(toolName: 'get_spending_by_category', args: {})],
        ),
      );
      expect(
        answer,
        isNot(
          const CopilotAnswer(
            text: 'You spent 34,200 on food in August.',
            trace: [],
          ),
        ),
      );
    });

    test('an answer with no tool calls is representable', () {
      // The model can answer without data ("what can you help me with?"), and
      // an empty trace is the honest rendering of that.
      const answer = CopilotAnswer(
        text: 'Ask me about your spending.',
        trace: [],
      );

      expect(answer.trace, isEmpty);
    });
  });
}
