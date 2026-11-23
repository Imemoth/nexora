import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';

import 'keyboard_actions.dart';
import 'strings/app_strings.dart';
import 'tasks_notifier.dart';
import 'theme/nexora_colors.dart';

/// First row of the list card: type a title, press Enter. It creates a root
/// task through the same path as the New task dialog, so validation, the
/// unsaved-change gate and the outbox rules all apply. Presentation only.
class QuickAddField extends StatefulWidget {
  const QuickAddField({super.key, required this.notifier});

  final TasksNotifier notifier;

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  FocusNode get _focus => TaskKeyboardFocus.of(widget.notifier).quickAdd;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The project a quick-added task goes to: the open project, otherwise the
  /// first one (the same default as the New task dialog).
  ({String id, String name})? _target() {
    final state = widget.notifier.state;
    if (state.projects.isEmpty) {
      return null;
    }
    final selection = state.selection;
    if (selection is ProjectSelection) {
      for (final project in state.projects) {
        if (project.id == selection.projectId) {
          return (id: project.id, name: project.name);
        }
      }
    }
    final first = state.projects.first;
    return (id: first.id, name: first.name);
  }

  Future<void> _submit() async {
    final target = _target();
    if (_busy || target == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.notifier.createRootTask(
      title: _controller.text,
      projectId: target.id,
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        _controller.clear();
        final gateOpened = widget.notifier.state.pending != null;
        setState(() => _busy = false);
        if (!gateOpened) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text(AppStrings.taskCreated)),
          );
        }
      case Err(:final error):
        setState(() {
          _busy = false;
          _error = AppStrings.errorMessage(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final target = _target();
    if (target == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(Icons.add, size: 18, color: c.text2),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('quick-add'),
                  controller: _controller,
                  focusNode: _focus,
                  enabled: !_busy,
                  onSubmitted: (_) {
                    _submit();
                    // Keep typing: the next task goes in without a click.
                    _focus.requestFocus();
                  },
                  style: NexoraText.body.copyWith(color: c.text1),
                  decoration: InputDecoration(
                    hintText: AppStrings.quickAddHint(target.name),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              _error!,
              key: const ValueKey('quick-add-error'),
              style: NexoraText.caption.copyWith(color: c.statusOverdue),
            ),
          ),
        Divider(height: 1, color: c.border),
      ],
    );
  }
}
