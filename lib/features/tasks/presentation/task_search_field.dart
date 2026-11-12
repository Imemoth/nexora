import 'package:flutter/material.dart';

import 'strings/app_strings.dart';

/// Search input. The workspace holds the query; this widget only mirrors it.
class TaskSearchField extends StatefulWidget {
  const TaskSearchField({
    super.key,
    required this.query,
    required this.onChanged,
    this.focusNode,
  });

  final String query;
  final ValueChanged<String> onChanged;

  /// Owned by the caller so Ctrl+F can focus the field from any pane.
  final FocusNode? focusNode;

  @override
  State<TaskSearchField> createState() => _TaskSearchFieldState();
}

class _TaskSearchFieldState extends State<TaskSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(covariant TaskSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The query can change from outside the field, for example when Clear is
    // pressed in the empty state.
    if (_controller.text != widget.query) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('search-field'),
      controller: _controller,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: AppStrings.searchHint,
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
