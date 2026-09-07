import 'package:equatable/equatable.dart';

/// What a tool produced after running on-device.
///
/// ## This type is the privacy boundary
///
/// [aggregate] is the only tool output that ever reaches the model, so it must
/// hold **computed summaries only** — category totals, income, deltas — in
/// integer minor units (C-4). It must never carry a transaction id, a merchant
/// string, a note, or receipt data (FR-COP-010, NFR-PRI-003).
///
/// The rule is enforced twice: tools are written to shape their own output, and
/// the egress guard test asserts the serialized request contains no raw-row
/// field. A type cannot express "summary of rows, not rows", so the test is the
/// part that actually holds.
class ToolResult extends Equatable {
  /// Creates an aggregate-only result.
  const ToolResult({required this.toolName, required this.aggregate});

  /// The tool that produced this, so the model can match it to its request.
  final String toolName;

  /// Aggregate-only payload, safe to send to the model.
  final Map<String, dynamic> aggregate;

  @override
  List<Object?> get props => [toolName, aggregate];
}
