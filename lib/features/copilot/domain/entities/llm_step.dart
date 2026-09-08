import 'package:equatable/equatable.dart';

import 'tool_call.dart';

/// One turn of the model's reasoning: either it wants tools run, or it is done.
///
/// Sealed so the loop's `switch` is exhaustive. A third kind of step — a
/// clarifying question, say — then fails to compile until the loop handles it,
/// rather than falling through a default branch and hanging the agent.
///
/// Refs: FR-COP-004.
sealed class LlmStep extends Equatable {
  /// Creates a step.
  const LlmStep();
}

/// The model wants one or more tools run before it can answer.
class ToolCallsRequested extends LlmStep {
  /// Creates a request for [calls].
  const ToolCallsRequested(this.calls);

  /// The requested calls, in the order the model asked for them. Unvalidated.
  final List<ToolCall> calls;

  @override
  List<Object?> get props => [calls];
}

/// The model has enough to answer, and this is the answer.
class FinalAnswer extends LlmStep {
  /// Creates a final answer.
  const FinalAnswer(this.text);

  /// The answer text, for the user to read.
  final String text;

  @override
  List<Object?> get props => [text];
}
