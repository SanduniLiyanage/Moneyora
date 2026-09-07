import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/agent_tool.dart';
import '../entities/llm_step.dart';
import '../entities/tool_result.dart';

/// The reasoning model, as the domain sees it.
///
/// One method, because reasoning is one operation: given the question, the
/// tools that exist, and everything the tools have returned so far, decide the
/// next step. The model holds no state between calls — the [history] is the
/// state, and it lives in the loop, which is what makes the loop testable
/// without a network.
///
/// The domain names no vendor. Swapping Gemini for another provider is a new
/// implementation in `data/datasources/` and one line in `injection.dart`;
/// this file, the loop and the tools do not change (NFR-POR-007).
///
/// Returns [ServerFailure] for a transport or provider error and
/// [NetworkFailure] when the device is offline — never throws, per the
/// repository convention.
abstract class LlmRepository {
  /// Asks the model what to do next.
  Future<Either<Failure, LlmStep>> reason({
    required String question,
    required List<AgentTool> tools,
    required List<ToolResult> history,
  });
}
