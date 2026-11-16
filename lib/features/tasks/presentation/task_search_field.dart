import 'package:flutter/material.dart';

import 'package:nexora/app/theme.dart';

import 'keycap.dart';
import 'strings/app_strings.dart';
import 'theme/nexora_colors.dart';

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
      style: NexoraText.body.copyWith(color: NexoraColors.of(context).text1),
      decoration: InputDecoration(
        hintText: AppStrings.searchHint,
        prefixIcon: const Icon(Icons.search, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 38),
        suffixIcon: const Padding(
          padding: EdgeInsets.only(right: 10),
          child: Keycap('Ctrl F'),
        ),
        suffixIconConstraints: const BoxConstraints(minHeight: 0),
        contentPadding: const EdgeInsets.symmetric(vertical: 9),
      ),
    );
  }
}
