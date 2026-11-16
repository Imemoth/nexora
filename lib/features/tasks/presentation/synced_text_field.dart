import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';

import 'theme/nexora_colors.dart';

/// A text field whose text mirrors an external value. The workspace draft is
/// the source of truth; this widget only keeps the controller in step with it.
class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.errorText,
    this.minLines = 1,
    this.maxLines = 1,
    this.focusNode,
    this.style,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? errorText;
  final int minLines;
  final int maxLines;

  /// Owned by the caller so keyboard commands can focus the field.
  final FocusNode? focusNode;

  /// Overrides the text style (the task title uses the field-title style).
  final TextStyle? style;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final field = TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      style: widget.style ?? NexoraText.body.copyWith(color: c.text1),
      decoration: InputDecoration(
        errorText: widget.errorText,
        // A failed field takes the overdue colour on its border.
        enabledBorder: widget.errorText == null
            ? null
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.statusOverdue),
              ),
      ),
    );
    final label = widget.label;
    if (label == null) {
      return field;
    }
    // The label sits above the field, not inside it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: NexoraText.label.copyWith(color: c.textMuted)),
        const SizedBox(height: 4),
        field,
      ],
    );
  }
}
