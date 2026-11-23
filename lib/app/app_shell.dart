import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/presentation/details_pane.dart';
import 'package:nexora/features/tasks/presentation/keyboard_actions.dart';
import 'package:nexora/features/tasks/presentation/reminder_strip.dart';
import 'package:nexora/features/tasks/presentation/reminders_notifier.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/task_list_pane.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';
import 'package:nexora/features/tasks/presentation/unsaved_changes_host.dart';
import 'package:nexora/platform/panel_width_store.dart';

import 'account_actions.dart';
import 'account_panel.dart';
import 'conflict_panel.dart';
import 'dashboard_pane.dart';
import 'details_overlay.dart';
import 'panel_resize.dart';
import 'sidebar_nav.dart';
import 'sync_alert_bar.dart';
import 'sync_panel.dart';

/// Responsive desktop layout.
///
/// - 1100 px and wider: sidebar, list and details side by side.
/// - 900 to 1099 px: the details editor is an overlay over the list, shown while
///   a task is selected. Closing it goes through the unsaved-change gate.
/// - Below 900 px: the desktop-only notice is shown, the list stays usable and
///   no overlay opens.
///
/// The sync alert bar sits above the panes, only for the critical sync states.
/// Account and sync status live in the sidebar card; reminders are a strip at
/// the top of the centre pane.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.onExitApp,
    this.syncPanel,
    this.accountPanel,
    this.importPanel,
    this.conflictPanel,
    this.panelWidths,
  });

  static const double sidebarWidth = 248;
  static const double detailsWidth = 380;
  static const double threePaneBreakpoint = 1100;
  static const double overlayBreakpoint = 900;

  /// Passed to the unsaved-change host. Tests inject a fake exit.
  final void Function()? onExitApp;

  /// Shown only when synchronization is enabled and wired; null by default.
  final SyncPanel? syncPanel;

  /// Shown only together with [syncPanel]; null by default.
  final AccountPanel? accountPanel;

  /// Non-null only for a signed-in account workspace.
  final ImportPanel? importPanel;

  /// Non-null only for a signed-in account workspace.
  final ConflictPanel? conflictPanel;

  /// Remembers the panel widths on this device. Null: not remembered.
  final PanelWidthStore? panelWidths;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Panel widths the user chose (three-pane layout only). They are clamped to
  // the window each build, so a smaller window never leaves a panel too wide.
  double _sidebarWidth = PanelLayout.sidebarDefault;
  double _detailsWidth = PanelLayout.detailsDefault;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    // The saved widths are the user's wish; the build fits them to the window.
    // Out-of-range values (an edited file) come back to the limits.
    final saved = widget.panelWidths?.load();
    if (saved != null) {
      _sidebarWidth = saved.sidebar.clamp(
        PanelLayout.sidebarMin,
        PanelLayout.sidebarMax,
      );
      _detailsWidth = saved.details.clamp(
        PanelLayout.detailsMin,
        PanelLayout.detailsMax,
      );
    }
  }

  /// Saves shortly after the last change, so a drag writes once, not per pixel.
  void _rememberWidths() {
    if (widget.panelWidths == null) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveWidths);
  }

  void _saveWidths() {
    _saveTimer?.cancel();
    _saveTimer = null;
    widget.panelWidths?.save(
      PanelWidths(sidebar: _sidebarWidth, details: _detailsWidth),
    );
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveWidths();
    }
    super.dispose();
  }

  void _closeOverlay(TasksNotifier notifier) {
    notifier.selectTask(null);
    // Return focus to the list's own keyboard node. The list keymap sits below
    // that node, so arrow keys and shortcuts reach it. A focus wrapper above
    // the list would not. Focus moves only when the close actually happened. A
    // dirty draft opens the gate instead, and the gate keeps focus.
    if (notifier.state.selectedTaskId == null) {
      final list = TaskKeyboardFocus.of(notifier).list;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          TaskKeyboardFocus.restore(list);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    final c = NexoraColors.of(context);
    final dashboard = state.selection is DashboardSelection;

    return UnsavedChangesHost(
      onExitApp: widget.onExitApp,
      child: Scaffold(
        backgroundColor: c.background,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final threePane = width >= AppShell.threePaneBreakpoint;
            final compact = width < AppShell.overlayBreakpoint;
            final overlayOpen =
                !threePane && !compact && !dashboard && state.draft != null;
            final showDetails = threePane && !dashboard;
            final emptyAccount =
                widget.importPanel != null &&
                !state.loading &&
                state.projects.isEmpty;

            final Widget centreBody;
            if (emptyAccount) {
              centreBody = EmptyAccountNotice(importPanel: widget.importPanel);
            } else if (dashboard) {
              // Ctrl+F works here too: it opens the All view and focuses search.
              centreBody = CallbackShortcuts(
                bindings: {
                  const SingleActivator(
                    LogicalKeyboardKey.keyF,
                    control: true,
                  ): () => TaskCommands(
                    notifier: notifier,
                    focus: TaskKeyboardFocus.of(notifier),
                    inEditor: false,
                  ).run(TaskCommand.focusSearch, context),
                },
                child: Focus(
                  autofocus: true,
                  child: DashboardPane(
                    syncPanel: widget.syncPanel,
                    accountPanel: widget.accountPanel,
                    conflictPanel: widget.conflictPanel,
                  ),
                ),
              );
            } else {
              centreBody = const TaskListPane(key: ValueKey('task-list-pane'));
            }

            final centre = Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (compact)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          AppStrings.desktopOnlyNotice,
                          key: const ValueKey('desktop-only-notice'),
                          style: NexoraText.body.copyWith(color: c.text2),
                        ),
                      ),
                    if (!dashboard && !emptyAccount && _hasReminders(context))
                      ReminderStrip(onShowDashboard: notifier.selectDashboard),
                    Expanded(child: centreBody),
                  ],
                ),
              ),
            );

            final widths = threePane
                ? PanelLayout.fit(_sidebarWidth, _detailsWidth, total: width)
                : (
                    sidebar: AppShell.sidebarWidth,
                    details: AppShell.detailsWidth,
                  );
            final rowOfPanes = Row(
              children: [
                SizedBox(
                  key: const ValueKey('sidebar'),
                  width: widths.sidebar,
                  child: SidebarNav(
                    syncPanel: widget.syncPanel,
                    accountPanel: widget.accountPanel,
                    importPanel: widget.importPanel,
                    conflictPanel: widget.conflictPanel,
                  ),
                ),
                centre,
                if (showDetails)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: c.border)),
                    ),
                    child: SizedBox(
                      key: const ValueKey('details-pane'),
                      width: widths.details,
                      child: const DetailsPane(),
                    ),
                  ),
              ],
            );
            // The handles sit on the pane borders and take no layout space, so
            // widths, breakpoints and the overlay are exactly as before.
            final panes = Stack(
              children: [
                rowOfPanes,
                if (threePane)
                  Positioned(
                    left: widths.sidebar - 5,
                    top: 0,
                    bottom: 0,
                    width: 10,
                    child: PanelResizeHandle(
                      key: const ValueKey('resize-sidebar'),
                      label: AppStrings.resizeSidebar,
                      value: widths.sidebar,
                      onChanged: (v) {
                        setState(
                          () => _sidebarWidth = PanelLayout.sidebar(
                            v,
                            total: width,
                            details: widths.details,
                          ),
                        );
                        _rememberWidths();
                      },
                      onReset: () {
                        setState(
                          () => _sidebarWidth = PanelLayout.sidebarDefault,
                        );
                        _rememberWidths();
                      },
                    ),
                  ),
                if (showDetails)
                  Positioned(
                    right: widths.details - 5,
                    top: 0,
                    bottom: 0,
                    width: 10,
                    child: PanelResizeHandle(
                      key: const ValueKey('resize-details'),
                      label: AppStrings.resizeDetails,
                      value: widths.details,
                      growsLeft: true,
                      onChanged: (v) {
                        setState(
                          () => _detailsWidth = PanelLayout.details(
                            v,
                            total: width,
                            sidebar: widths.sidebar,
                          ),
                        );
                        _rememberWidths();
                      },
                      onReset: () {
                        setState(
                          () => _detailsWidth = PanelLayout.detailsDefault,
                        );
                        _rememberWidths();
                      },
                    ),
                  ),
              ],
            );

            final sync = widget.syncPanel;
            final content = Column(
              children: [
                if (sync != null)
                  SyncAlertBar(
                    syncPanel: sync,
                    accountPanel: widget.accountPanel,
                    conflictPanel: widget.conflictPanel,
                  ),
                Expanded(child: panes),
              ],
            );

            return Stack(
              children: [
                content,
                if (overlayOpen)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: AppShell.detailsWidth,
                    child: DetailsOverlay(
                      key: const ValueKey('details-overlay'),
                      onClose: () => _closeOverlay(notifier),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _hasReminders(BuildContext context) =>
      ReminderScope.maybeOf(context) != null;
}
