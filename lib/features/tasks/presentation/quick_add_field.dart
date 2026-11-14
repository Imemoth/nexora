import 'package:flutter/material.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';

import 'strings/app_strings.dart';
import 'tasks_notifier.dart';
import 'theme/nexora_colors.dart';

/// Adds a root task from one line. Enter creates it in the selected project, or
/// in the first project when a smart view is selected, and clears the field.
/// An error stays under the field with the typed title kept. It uses the same
/// creation path as the New task dialog, so every rule and the unsaved-change
/// gate apply.
class QuickAddField extends StatefulWidget {
  const QuickAddField({super.key, required this.notifier});

  final TasksNotifier notifier;

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? _targetProjectId() {
    final state = widget.notifier.state;
    final selection = state.selection;
    if (selection is ProjectSelection) {
      return selection.projectId;
    }
    return state.projects.isEmpty ? null : state.projects.first.id;
  }

  Future<void> _submit() async {
    final projectId = _targetProjectId();
    if (_busy || projectId == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.notifier.createRootTask(
      title: _controller.text,
      projectId: projectId,
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        _controller.clear();
        setState(() => _busy = false);
        _focus.requestFocus();
      case Err(:final error):
        setState(() {
          _busy = false;
          _error = AppStrings.errorMessage(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NexoraColors.of(context);
    return TextField(
      key: const ValueKey('quick-add'),
      controller: _controller,
      focusNode: _focus,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        hintText: AppStrings.quickAddHint,
        isDense: true,
        errorText: _error,
        prefixIcon: Icon(Icons.add, color: colors.text2),
      ),
    );
  }
}
