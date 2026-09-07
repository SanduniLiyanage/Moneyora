import 'package:equatable/equatable.dart';

/// The declaration of a tool the agent may ask for, as the model sees it.
///
/// This is the whole of what the LLM knows about a tool: a [name], a
/// [description] telling it when the tool is useful, and a JSON-Schema
/// [parameters] map. The model never runs anything — it only *asks* for a tool
/// by name, and the loop executes it on-device.
///
/// Keeping the declaration a value rather than a hard-coded block in the
/// request builder is what makes a new tool a registration and not a change to
/// the loop (NFR-POR-007).
///
/// Refs: FR-COP-006, NFR-POR-007.
class AgentTool extends Equatable {
  /// Creates a tool declaration.
  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// Unique tool name, e.g. `get_spending_by_category`.
  ///
  /// This is the key the loop looks up when the model asks for the tool, so it
  /// must match the registry key exactly.
  final String name;

  /// Plain-language description the model uses to decide when to call this.
  final String description;

  /// JSON-Schema-shaped argument description, e.g.
  /// `{'type': 'object', 'properties': {'from': {'type': 'string'}}}`.
  ///
  /// A `Map` rather than a typed schema class because it is handed straight to
  /// the provider's function-calling API, and every provider spells the same
  /// schema slightly differently. Typing it here would buy nothing and would
  /// have to be undone in the data layer.
  final Map<String, dynamic> parameters;

  @override
  List<Object?> get props => [name, description, parameters];
}
