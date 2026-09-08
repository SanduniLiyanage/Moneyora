import 'package:equatable/equatable.dart';

import 'tool_call.dart';

/// What the Copilot screen shows: the answer, and how it was reached.
///
/// The [trace] is not debug output. An answer about someone's own money is
/// worth little if they cannot see where the numbers came from, so FR-COP-003
/// makes the tool list part of the answer — "I looked at your August spending
/// and your savings goal" — rather than something hidden behind a developer
/// flag.
class CopilotAnswer extends Equatable {
  /// Creates an answer with its tool-use trace.
  const CopilotAnswer({required this.text, required this.trace});

  /// The model's final text, in the user's own terms (NFR-USA-005).
  final String text;

  /// The tool calls that were actually executed, in order. Empty when the
  /// model answered without needing any data.
  final List<ToolCall> trace;

  @override
  List<Object?> get props => [text, trace];
}
