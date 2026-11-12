import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';

import 'strings/app_strings.dart';
import 'tasks_notifier.dart';
import 'tasks_scope.dart';

/// Opens the unsaved-change dialog whenever the workspace has a pending
/// transition, and answers application exit requests.
///
/// One listener covers every route into the gate: mouse, keyboard, creation
/// and exit. The dialog stays open while a save fails, so the user never loses
/// edits silently.
class UnsavedChangesHost extends StatefulWidget {
  const UnsavedChangesHost({super.key, required this.child, this.onExitApp});

  final Widget child;

  /// Called after a Save or Discard answer allows exit. Defaults to asking
  /// the platform to exit. Tests inject a fake.
  final void Function()? onExitApp;

  @override
  State<UnsavedChangesHost> createState() => UnsavedChangesHostState();
}

class UnsavedChangesHostState extends State<UnsavedChangesHost> {
  TasksNotifier? _notifier;
  bool _dialogOpen = false;
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: handleExitRequest,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TasksScope.of(context);
    if (!identical(notifier, _notifier)) {
      _notifier?.removeListener(_onChanged);
      _notifier = notifier;
      notifier.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _notifier?.removeListener(_onChanged);
    _lifecycle.dispose();
    super.dispose();
  }

  /// Answers an application exit request. A clean workspace exits. A dirty
  /// one cancels the exit and opens the gate.
  @visibleForTesting
  Future<AppExitResponse> handleExitRequest() async {
    final allowed = await _notifier!.requestExit();
    return allowed ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  void _onChanged() {
    if (!mounted || _dialogOpen) {
      return;
    }
    if (_notifier?.state.pending == null) {
      return;
    }
    _dialogOpen = true;
    // Open after the current frame. The creation dialog may still be on
    // screen while this notification is delivered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _dialogOpen = false;
        return;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UnsavedChangesDialog(
          notifier: _notifier!,
          onExitApp: widget.onExitApp ?? _exitApplication,
        ),
      ).whenComplete(() => _dialogOpen = false);
    });
  }

  static void _exitApplication() {
    ServicesBinding.instance.exitApplication(AppExitType.required);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UnsavedChangesDialog extends StatelessWidget {
  const _UnsavedChangesDialog({
    required this.notifier,
    required this.onExitApp,
  });

  final TasksNotifier notifier;
  final void Function() onExitApp;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        final error = notifier.state.error;
        return AlertDialog(
          title: const Text(AppStrings.unsavedChangesTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(AppStrings.unsavedChangesBody),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    AppStrings.errorMessage(error),
                    key: const ValueKey('gate-error'),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              key: const ValueKey('gate-cancel'),
              onPressed: () => _resolve(context, PendingResolution.cancel),
              child: const Text(AppStrings.cancelAction),
            ),
            TextButton(
              key: const ValueKey('gate-discard'),
              onPressed: () => _resolve(context, PendingResolution.discard),
              child: const Text(AppStrings.discardAction),
            ),
            FilledButton(
              key: const ValueKey('gate-save'),
              onPressed: () => _resolve(context, PendingResolution.save),
              child: const Text(AppStrings.saveAction),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resolve(
    BuildContext context,
    PendingResolution resolution,
  ) async {
    await notifier.resolvePending(resolution);
    if (!context.mounted) {
      return;
    }
    // A failed save leaves the gate open, so the dialog stays with the error.
    if (notifier.state.pending == null) {
      Navigator.of(context).pop();
    }
    if (notifier.state.exitReady) {
      onExitApp();
    }
  }
}
