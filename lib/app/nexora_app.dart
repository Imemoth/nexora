import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_scope.dart';

import 'app_shell.dart';
import 'account_actions.dart';
import 'account_panel.dart';
import 'conflict_panel.dart';
import 'sync_panel.dart';
import 'theme.dart';

class NexoraApp extends StatefulWidget {
  const NexoraApp({
    super.key,
    required this.notifier,
    this.themeController,
    this.onExitApp,
    this.textScaler,
    this.syncPanel,
    this.accountPanel,
    this.importPanel,
    this.conflictPanel,
  });

  final TasksNotifier notifier;

  /// The theme choice. When null the app uses an in-memory controller that
  /// starts in dark mode, which keeps tests deterministic.
  final ThemeController? themeController;

  final void Function()? onExitApp;

  final TextScaler? textScaler;

  /// Null unless synchronization is enabled and wired (it is not, by default).
  final SyncPanel? syncPanel;

  /// Null unless synchronization is enabled and wired (it is not, by default).
  final AccountPanel? accountPanel;

  /// Null unless a signed-in account workspace is shown.
  final ImportPanel? importPanel;

  /// Non-null only for a signed-in account workspace.
  final ConflictPanel? conflictPanel;

  @override
  State<NexoraApp> createState() => _NexoraAppState();
}

class _NexoraAppState extends State<NexoraApp> {
  ThemeController? _ownController;

  ThemeController get _theme =>
      widget.themeController ??
      (_ownController ??= ThemeController(
        InMemorySettingsStore(ThemePreference.dark),
        initial: ThemePreference.dark,
      ));

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _theme;
    return TasksScope(
      notifier: widget.notifier,
      child: ThemeScope(
        controller: controller,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => MaterialApp(
            title: AppStrings.appName,
            debugShowCheckedModeBanner: false,
            themeMode: controller.mode,
            theme: buildNexoraLightTheme(),
            darkTheme: buildNexoraDarkTheme(),
            builder: (context, child) {
              final scaler = widget.textScaler;
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
              onExitApp: widget.onExitApp,
              syncPanel: widget.syncPanel,
              accountPanel: widget.accountPanel,
              importPanel: widget.importPanel,
              conflictPanel: widget.conflictPanel,
            ),
          ),
        ),
      ),
    );
  }
}
