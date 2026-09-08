import 'package:equatable/equatable.dart';

import 'tool_call.dart';
import 'tool_result.dart';

/// One completed round trip: what the model asked for, and what it got back.
///
/// The pair travels together because a function-calling API records a
/// conversation, not a list of answers — the model's own request has to appear
/// in the transcript before the response to it, or the provider is being told
/// about a reply to something that was never asked.
///
/// It is also what lets the model see that its second call differs from its
/// first: two results with the same tool name and different arguments are
/// indistinguishable without the call beside them.
class ToolExchange extends Equatable {
  /// Pairs [call] with the [result] running it produced.
  const ToolExchange({required this.call, required this.result});

  /// What the model asked for.
  final ToolCall call;

  /// What running it produced — aggregates only (FR-COP-010).
  final ToolResult result;

  @override
  List<Object?> get props => [call, result];
}
