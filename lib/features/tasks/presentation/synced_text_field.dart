import 'package:flutter/material.dart';

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
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? errorText;
  final int minLines;
  final int maxLines;

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
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
