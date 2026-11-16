import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/focus_ring.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_scope.dart';

import 'about_dialog.dart';
import 'account_actions.dart';
import 'account_panel.dart';

/// The account row at the bottom of the sidebar and the menu it opens: Theme,
/// Import local data, Keyboard shortcuts, Sign in or Sign out. Every item calls
/// the existing function; nothing here is new engine behaviour.
///
/// With synchronization off ([panel] null) the menu holds only Theme and
/// Keyboard shortcuts: Sign in, Import local data and Sign out are hidden.
class AccountMenu extends StatelessWidget {
  const AccountMenu({
    super.key,
    required this.label,
    required this.signedIn,
    this.panel,
    this.importPanel,
  });

  /// "Signed in as ..." or "Local workspace".
  final String label;
  final bool signedIn;
  final AccountPanel? panel;
  final ImportPanel? importPanel;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final theme = ThemeScope.maybeOf(context);
    final accountPanel = panel;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: const MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(224, 0)),
        padding: WidgetStatePropertyAll(EdgeInsets.all(6)),
      ),
      builder: (context, controller, child) {
        return FocusRing(
          radius: 8,
          child: InkWell(
            key: const ValueKey('account-row'),
            borderRadius: BorderRadius.circular(8),
            hoverColor: c.surface2,
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Tooltip(
              message: AppStrings.accountMenuTooltip,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 16, color: c.text2),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        key: const ValueKey('account-status-text'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NexoraText.caption.copyWith(color: c.text2),
                      ),
                    ),
                    Icon(Icons.expand_less, size: 16, color: c.text2),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      menuChildren: [
        if (theme != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.themeLabel,
                  style: NexoraText.label.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: 6),
                ListenableBuilder(
                  listenable: theme,
                  builder: (context, _) => SegmentedButton<ThemePreference>(
                    key: const ValueKey('theme-selector'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemePreference.system,
                        label: Text(AppStrings.themeSystem),
                      ),
                      ButtonSegment(
                        value: ThemePreference.light,
                        label: Text(AppStrings.themeLight),
                      ),
                      ButtonSegment(
                        value: ThemePreference.dark,
                        label: Text(AppStrings.themeDark),
                      ),
                    ],
                    selected: {theme.preference},
                    onSelectionChanged: (selection) =>
                        theme.select(selection.first),
                  ),
                ),
              ],
            ),
          ),
        if (signedIn && importPanel != null)
          MenuItemButton(
            key: const ValueKey('bar-import'),
            leadingIcon: const Icon(Icons.download_outlined, size: 18),
            onPressed: () => showImportDialog(context, importPanel!),
            child: const Text(AppStrings.importLocalAction),
          ),
        MenuItemButton(
          key: const ValueKey('menu-about'),
          leadingIcon: const Icon(Icons.info_outline, size: 18),
          onPressed: () => showAboutNexoraDialog(context),
          child: const Text(AppStrings.aboutAction),
        ),
        MenuItemButton(
          key: const ValueKey('menu-shortcuts'),
          leadingIcon: const Icon(Icons.keyboard_outlined, size: 18),
          onPressed: () => showShortcutsDialog(context),
          child: const Text(AppStrings.shortcutsAction),
        ),
        if (accountPanel != null && signedIn)
          MenuItemButton(
            key: const ValueKey('sign-out'),
            leadingIcon: const Icon(Icons.logout, size: 18),
            // Signing out replaces the workspace, so it goes through the
            // unsaved-change gate like any other navigation.
            onPressed: () =>
                TasksScope.of(context).requestSignOut(accountPanel.signOut),
            child: const Text(AppStrings.signOutAction),
          ),
        if (accountPanel != null && !signedIn)
          MenuItemButton(
            key: const ValueKey('menu-sign-in'),
            leadingIcon: const Icon(Icons.login, size: 18),
            onPressed: () => showSignInDialog(context, accountPanel),
            child: const Text(AppStrings.signInAction),
          ),
      ],
    );
  }
}

/// Lists the keyboard map. No shortcut is added by Phase 5.
Future<void> showShortcutsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final c = NexoraColors.of(context);
      return AlertDialog(
        key: const ValueKey('shortcuts-dialog'),
        title: const Text(AppStrings.shortcutsTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (keys, action) in AppStrings.shortcutList)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          keys,
                          style: NexoraText.keycap.copyWith(
                            color: c.accentCyan,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          action,
                          style: NexoraText.body.copyWith(color: c.text2),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('shortcuts-close'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.closeAction),
          ),
        ],
      );
    },
  );
}
