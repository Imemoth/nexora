import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/reminder_service.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/platform/desktop_integration.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';

import 'app_shell.dart';
import 'account_actions.dart';
import 'account_panel.dart';
import 'conflict_panel.dart';
import 'desktop_bridge.dart';
import 'sync_panel.dart';
import 'theme.dart';

/// Application root: the approved dark theme, the task workspace scope and the
/// shell. No network, no persistence and no configuration.
class NexoraApp extends StatelessWidget {
  const NexoraApp({
    super.key,
    required this.notifier,
    this.onExitApp,
    this.textScaler,
    this.syncPanel,
    this.accountPanel,
    this.importPanel,
    this.conflictPanel,
    this.desktop,
    this.reminders,
    this.beforeExit,
  });

  final TasksNotifier notifier;

  /// Test seam for the exit action. Production uses the platform exit.
  final void Function()? onExitApp;

  /// Test seam for text scaling. Null keeps the platform scaling.
  final TextScaler? textScaler;

  /// Null unless synchronization is enabled and wired (it is not, by default).
  final SyncPanel? syncPanel;

  /// Null unless synchronization is enabled and wired (it is not, by default).
  final AccountPanel? accountPanel;

  /// Null unless a signed-in account workspace is shown.
  final ImportPanel? importPanel;

  /// Non-null only for a signed-in account workspace.
  final ConflictPanel? conflictPanel;

  /// Tray and native notifications (null in tests and on other platforms).
  final DesktopIntegration? desktop;

  /// The device-local reminders of this workspace; null hides the reminder UI.
  final ReminderService? reminders;

  /// Called before an explicit Exit ends the process.
  final Future<void> Function()? beforeExit;

  @override
  Widget build(BuildContext context) {
    return TasksScope(
      notifier: notifier,
      child: DesktopBridge(
        desktop: desktop,
        reminders: reminders,
        beforeExit: beforeExit,
        child: MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          theme: buildNexoraDarkTheme(),
          darkTheme: buildNexoraDarkTheme(),
          builder: (context, child) {
            final scaler = textScaler;
            final content = child ?? const SizedBox.shrink();
            if (scaler == null) {
              return content;
            }
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: scaler),
              child: content,
            );
          },
          home: AppShell(
            onExitApp: onExitApp,
            syncPanel: syncPanel,
            accountPanel: accountPanel,
            importPanel: importPanel,
            conflictPanel: conflictPanel,
          ),
        ),
      ),
    );
  }
}
