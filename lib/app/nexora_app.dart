import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';

import 'app_shell.dart';
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
  });

  final TasksNotifier notifier;

  /// Test seam for the exit action. Production uses the platform exit.
  final void Function()? onExitApp;

  /// Test seam for text scaling. Null keeps the platform scaling.
  final TextScaler? textScaler;

  /// Null unless synchronization is enabled and wired (it is not, by default).
  final SyncPanel? syncPanel;

  @override
  Widget build(BuildContext context) {
    return TasksScope(
      notifier: notifier,
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
        home: AppShell(onExitApp: onExitApp, syncPanel: syncPanel),
      ),
    );
  }
}
