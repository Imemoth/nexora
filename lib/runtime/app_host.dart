import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexora/core/build_info.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';
import 'package:nexora/platform/desktop_integration.dart';
import 'package:nexora/platform/panel_width_store.dart';

import 'sync_runtime.dart';

/// Shows the application for whichever workspace the runtime has open, and
/// rebuilds it when the account changes. Used only when synchronization is
/// enabled; the default application runs [NexoraApp] directly.
class AppHost extends StatefulWidget {
  const AppHost({
    super.key,
    required this.runtime,
    this.onExitApp,
    this.desktop,
    this.themeController,
    this.buildInfo,
    this.panelWidths,
  });

  final SyncRuntime runtime;
  final void Function()? onExitApp;

  /// Tray and native notifications; null disables them.
  final DesktopIntegration? desktop;

  /// The device-level theme choice; survives an account switch.
  final ThemeController? themeController;

  /// Which build is running (About).
  final BuildInfo? buildInfo;

  /// Panel widths remembered on this device; survive an account switch.
  final PanelWidthStore? panelWidths;

  @override
  State<AppHost> createState() => _AppHostState();
}

class _AppHostState extends State<AppHost> {
  late ActiveWorkspace _active;
  late TasksNotifier _notifier;
  StreamSubscription<ActiveWorkspace>? _subscription;

  @override
  void initState() {
    super.initState();
    _active = widget.runtime.active;
    _notifier = TasksNotifier(_active.workspace);
    _subscription = widget.runtime.workspaceChanges.listen(_swap);
  }

  Future<void> _swap(ActiveWorkspace next) async {
    await next.workspace.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _active = next;
      _notifier = TasksNotifier(next.workspace);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NexoraApp(
      key: ValueKey(_active.userId ?? 'local'),
      notifier: _notifier,
      onExitApp: widget.onExitApp,
      desktop: widget.desktop,
      themeController: widget.themeController,
      buildInfo: widget.buildInfo,
      panelWidths: widget.panelWidths,
      reminders: _active.reminders,
      beforeExit: widget.runtime.dispose,
      syncPanel: widget.runtime.syncPanel(),
      accountPanel: widget.runtime.accountPanel(),
      importPanel: widget.runtime.importPanel(),
      conflictPanel: widget.runtime.conflictPanel(),
    );
  }
}
