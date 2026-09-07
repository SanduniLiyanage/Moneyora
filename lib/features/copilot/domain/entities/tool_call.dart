import 'package:equatable/equatable.dart';

/// One tool invocation the model has asked for.
///
/// Produced by parsing the model's response, so **nothing here is trusted**:
/// [toolName] may name a tool that does not exist and [args] may be missing,
/// mistyped, or nonsense. The loop validates both before executing anything
/// (FR-COP-006), which is why this is a plain record of a request rather than
/// a command that knows how to run itself.
///
/// Refs: FR-COP-004, FR-COP-006.
class ToolCall extends Equatable {
  /// Creates a requested call.
  const ToolCall({required this.toolName, required this.args});

  /// The tool the model asked for. Unvalidated.
  final String toolName;

  /// The arguments the model supplied. Unvalidated.
  final Map<String, dynamic> args;

  @override
  List<Object?> get props => [toolName, args];
}
