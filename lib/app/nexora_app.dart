import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';

import 'app_shell.dart';

/// Application root: dark theme, the task workspace scope and the shell.
/// No network, no persistence and no configuration.
class NexoraApp extends StatelessWidget {
  const NexoraApp({super.key, required this.notifier, this.onExitApp});

  final TasksNotifier notifier;

  /// Test seam for the exit action. Production uses the platform exit.
  final void Function()? onExitApp;

  @override
  Widget build(BuildContext context) {
    return TasksScope(
      notifier: notifier,
      child: MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
        darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: AppShell(onExitApp: onExitApp),
      ),
    );
  }
}
