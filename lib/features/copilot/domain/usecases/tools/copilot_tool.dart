import 'package:fpdart/fpdart.dart';

import '../../../../../core/errors/failures.dart';
import '../../entities/agent_tool.dart';
import '../../entities/tool_result.dart';

/// One thing the agent can do on-device.
///
/// A tool is two halves that must agree: the [descriptor] the model reads when
/// deciding what to call, and [execute], which does the work. When they drift —
/// a parameter renamed in one and not the other — the model asks for something
/// the tool rejects, and the agent quietly gets worse rather than failing. Both
/// live in one class for that reason.
///
/// Tools add no business logic. Each wraps an existing Moneyora use case or a
/// narrow read port and shapes the output into an aggregate (FR-COP-022).
///
/// ## Why this returns `Either` rather than throwing
///
/// [execute]'s arguments come from a language model, so malformed input is
/// ordinary rather than exceptional, and FR-COP-006 requires rejecting it
/// without crashing. Returning a [ValidationFailure] keeps that on the normal
/// path, and keeps the loop free of the `try`/`catch` the repo forbids above
/// `data/`. It is the same shape every use case in the app already has.
///
/// Refs: FR-COP-006, FR-COP-007..015, FR-COP-020..022, NFR-MNT-006.
abstract class CopilotTool {
  /// What the model is told about this tool.
  AgentTool get descriptor;

  /// Runs the tool against the local database.
  ///
  /// Returns `Left(ValidationFailure)` when [args] cannot be used, and never
  /// throws.
  Future<Either<Failure, ToolResult>> execute(Map<String, dynamic> args);
}
