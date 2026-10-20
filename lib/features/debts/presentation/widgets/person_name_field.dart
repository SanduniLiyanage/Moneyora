import 'package:flutter/material.dart';

import '../../domain/entities/debt_person.dart';

/// A name field that offers the people already recorded, as they are
/// typed. FR-DBT-006, E-47.
///
/// People are grouped by name (FR-DBT-005), so a second spelling of one
/// person is a second person. Offering the spelling already used, the
/// moment the first letters match, is what keeps "Nimal" from becoming
/// "Nimal" and "nimal p" by accident. A suggestion is only offered: what
/// is typed is what is saved.
class PersonNameField extends StatefulWidget {
  /// Creates the field over [controller], suggesting from [names].
  const PersonNameField({
    required this.controller,
    required this.names,
    required this.decoration,
    this.autofocus = false,
    super.key,
  });

  /// Holds the name.
  final TextEditingController controller;

  /// Everyone recorded so far, one spelling each.
  final List<String> names;

  /// The field's label, hint and error.
  final InputDecoration decoration;

  /// Whether the field takes focus when shown.
  final bool autofocus;

  /// The most suggestions shown at once.
  static const int maxSuggestions = 5;

  /// The names in [names] that [typed] could be: those starting with it
  /// first, then those containing it, matched as people are; none for an
  /// empty field, and not the one already typed exactly.
  static List<String> suggestionsFor(String typed, List<String> names) {
    final needle = personKey(typed);
    if (needle.isEmpty) return const [];
    final starts = <String>[];
    final contains = <String>[];
    for (final name in names) {
      if (name == typed.trim()) continue;
      final key = personKey(name);
      if (key.startsWith(needle)) {
        starts.add(name);
      } else if (key.contains(needle)) {
        contains.add(name);
      }
    }
    return [...starts, ...contains].take(maxSuggestions).toList();
  }

  @override
  State<PersonNameField> createState() => _PersonNameFieldState();
}

class _PersonNameFieldState extends State<PersonNameField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) =>
          PersonNameField.suggestionsFor(value.text, widget.names),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: widget.autofocus,
            textCapitalization: TextCapitalization.words,
            decoration: widget.decoration,
            onSubmitted: (_) => onSubmitted(),
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: AlignmentDirectional.topStart,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 240,
              // No wider than the screen less its margins.
              maxWidth: MediaQuery.sizeOf(context).width - 32,
            ),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final name in options)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(name),
                    onTap: () => onSelected(name),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
