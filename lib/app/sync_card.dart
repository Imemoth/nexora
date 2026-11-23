import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

import 'account_actions.dart';
import 'account_menu.dart';
import 'account_panel.dart';
import 'conflict_dialog.dart';
import 'conflict_panel.dart';
import 'sync_panel.dart';
import 'sync_presentation.dart';

/// The two panels' current values, resolved once for one frame.
typedef PanelValues = ({SyncStatus status, AccountView? account});

/// Rebuilds [builder] whenever the sync status or the account view changes.
/// Either panel may be absent (synchronization off).
class PanelStreams extends StatelessWidget {
  const PanelStreams({
    super.key,
    required this.syncPanel,
    required this.accountPanel,
    required this.builder,
  });

  final SyncPanel? syncPanel;
  final AccountPanel? accountPanel;
  final Widget Function(BuildContext context, PanelValues values) builder;

  @override
  Widget build(BuildContext context) {
    return _accountLayer(
      (account) => _statusLayer(
        (status) => builder(context, (status: status, account: account)),
      ),
    );
  }

  Widget _accountLayer(Widget Function(AccountView? account) inner) {
    final panel = accountPanel;
    if (panel == null) {
      return inner(null);
    }
    return StreamBuilder<AccountView>(
      stream: panel.views,
      initialData: panel.initial,
      builder: (context, snapshot) => inner(snapshot.data ?? panel.initial),
    );
  }

  Widget _statusLayer(Widget Function(SyncStatus status) inner) {
    final panel = syncPanel;
    if (panel == null) {
      return inner(const SyncStatus(phase: SyncPhase.disabled));
    }
    return StreamBuilder<SyncStatus>(
      stream: panel.statuses,
      initialData: panel.initial,
      builder: (context, snapshot) => inner(snapshot.data ?? panel.initial),
    );
  }
}

/// Whether the account counts as signed in for [describeSync]. Without an
/// account panel, a running sync is by definition for a signed-in workspace.
bool isSignedIn(AccountPanel? panel, AccountView? account) {
  if (panel == null) {
    return true;
  }
  return account != null && account.phase != AccountPhase.signedOut;
}

/// Runs the action a [SyncPresentation] asks for. Shared by the card, the alert
/// bar and the dashboard so all three behave the same.
VoidCallback? syncActionHandler(
  BuildContext context, {
  required SyncPresentation presentation,
  required SyncStatus status,
  SyncPanel? syncPanel,
  AccountPanel? accountPanel,
  ConflictPanel? conflictPanel,
}) {
  switch (presentation.action) {
    case SyncAction.none:
      return null;
    case SyncAction.syncNow:
      if (syncPanel == null || status.phase == SyncPhase.syncing) {
        return null;
      }
      return () => syncPanel.syncNow();
    case SyncAction.resolve:
      if (conflictPanel == null) {
        return syncPanel == null ? null : () => syncPanel.syncNow();
      }
      return () => showConflictDialog(context, conflictPanel);
    case SyncAction.signIn:
      if (accountPanel == null) {
        return null;
      }
      return () => showSignInDialog(context, accountPanel);
  }
}

/// The label of a presentation's action button.
String syncActionLabel(SyncAction action) => switch (action) {
  SyncAction.none => '',
  SyncAction.syncNow => AppStrings.syncNowAction,
  SyncAction.resolve => AppStrings.resolveAction,
  SyncAction.signIn => AppStrings.signInAction,
};

/// The stable key name of an action button, kept from the bars it replaces.
String syncActionKeyName(SyncAction action) => switch (action) {
  SyncAction.none => 'sync-action-none',
  SyncAction.syncNow => 'sync-now',
  SyncAction.resolve => 'sync-conflicts',
  SyncAction.signIn => 'sign-in',
};

Color syncBorderColor(NexoraColors c, SyncBorder border) => switch (border) {
  SyncBorder.normal => c.border,
  SyncBorder.warning => c.severityWarning,
  SyncBorder.critical => c.severityCritical,
};

/// Sidebar card at the bottom: the sync state in words, its one action, and
/// the account row that opens the account menu.
class SyncCard extends StatefulWidget {
  const SyncCard({
    super.key,
    this.syncPanel,
    this.accountPanel,
    this.importPanel,
    this.conflictPanel,
  });

  final SyncPanel? syncPanel;
  final AccountPanel? accountPanel;
  final ImportPanel? importPanel;
  final ConflictPanel? conflictPanel;

  @override
  State<SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<SyncCard> {
  StreamSubscription<AccountView>? _notices;
  AccountNotice _lastNotice = AccountNotice.none;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant SyncCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.accountPanel, widget.accountPanel)) {
      _notices?.cancel();
      _listen();
    }
  }

  void _listen() {
    final panel = widget.accountPanel;
    if (panel == null) {
      return;
    }
    _notices = panel.views.listen(_onView);
  }

  /// Session notices become quiet snackbars. A session that ended is the Sign
  /// in needed state, so it is not repeated here.
  void _onView(AccountView view) {
    final notice = view.notice;
    if (notice == _lastNotice) {
      return;
    }
    _lastNotice = notice;
    if (notice == AccountNotice.none ||
        notice == AccountNotice.sessionExpired) {
      return;
    }
    final text = accountNoticeText(notice);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));
    });
  }

  @override
  void dispose() {
    _notices?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PanelStreams(
      syncPanel: widget.syncPanel,
      accountPanel: widget.accountPanel,
      builder: (context, values) {
        final signedIn = isSignedIn(widget.accountPanel, values.account);
        final presentation = describeSync(values.status, signedIn: signedIn);
        final handler = syncActionHandler(
          context,
          presentation: presentation,
          status: values.status,
          syncPanel: widget.syncPanel,
          accountPanel: widget.accountPanel,
          conflictPanel: widget.conflictPanel,
        );
        final account = values.account;
        final accountLabel =
            account != null &&
                account.phase != AccountPhase.signedOut &&
                (account.email ?? '').isNotEmpty
            ? AppStrings.accountSignedInAs(account.email!)
            : AppStrings.accountLocalShort;
        return _CardBody(
          presentation: presentation,
          action: handler,
          accountLabel: accountLabel,
          signedIn:
              widget.accountPanel != null &&
              account != null &&
              account.phase == AccountPhase.signedIn,
          accountPanel: widget.accountPanel,
          importPanel: widget.importPanel,
        );
      },
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.presentation,
    required this.action,
    required this.accountLabel,
    required this.signedIn,
    required this.accountPanel,
    required this.importPanel,
  });

  final SyncPresentation presentation;
  final VoidCallback? action;
  final String accountLabel;
  final bool signedIn;
  final AccountPanel? accountPanel;
  final ImportPanel? importPanel;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final tint = _levelColor(c);
    final border = syncBorderColor(c, presentation.border);
    // The action appears only when it can run: no panel, no button.
    final hasAction = action != null;
    return Container(
      key: const ValueKey('sync-status-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: border,
          width: presentation.thickBorder ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The action sits beside the title when both fit, and drops under it
          // in a narrow sidebar, so the title is never squeezed to nothing.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 2,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LevelIcon(level: presentation.level, color: tint),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Semantics(
                      liveRegion: true,
                      child: Tooltip(
                        message: presentation.title,
                        waitDuration: const Duration(milliseconds: 500),
                        child: Text(
                          presentation.title,
                          key: const ValueKey('sync-title'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: NexoraText.bodyStrong.copyWith(color: tint),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (hasAction)
                TextButton(
                  key: ValueKey(syncActionKeyName(presentation.action)),
                  onPressed: action,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(syncActionLabel(presentation.action)),
                ),
            ],
          ),
          if (presentation.sentence.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              presentation.sentence,
              key: const ValueKey('sync-status-text'),
              style: NexoraText.caption.copyWith(color: c.text2),
            ),
          ],
          const SizedBox(height: 8),
          Divider(height: 1, color: c.border),
          AccountMenu(
            label: accountLabel,
            signedIn: signedIn,
            panel: accountPanel,
            importPanel: importPanel,
          ),
        ],
      ),
    );
  }

  Color _levelColor(NexoraColors c) {
    return switch (presentation.level) {
      SyncLevel.ok => c.statusDone,
      SyncLevel.busy => c.text1,
      SyncLevel.info => c.statusOpen,
      SyncLevel.warning => c.severityWarning,
      SyncLevel.critical =>
        presentation.barSeverity == SyncBorder.warning
            ? c.severityWarning
            : c.severityCritical,
      SyncLevel.off => c.text2,
    };
  }
}

/// 16 px level icon. The synchronizing icon turns, unless animations are off.
class _LevelIcon extends StatefulWidget {
  const _LevelIcon({required this.level, required this.color});

  final SyncLevel level;
  final Color color;

  @override
  State<_LevelIcon> createState() => _LevelIconState();
}

class _LevelIconState extends State<_LevelIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LevelIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate =
        widget.level == SyncLevel.busy &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!animate && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  IconData get _icon => switch (widget.level) {
    SyncLevel.ok => Icons.check_circle_outline,
    SyncLevel.busy => Icons.sync,
    SyncLevel.info => Icons.cloud_upload_outlined,
    SyncLevel.warning => Icons.cloud_off,
    SyncLevel.critical => Icons.warning_amber,
    SyncLevel.off => Icons.cloud_off,
  };

  @override
  Widget build(BuildContext context) {
    final icon = Icon(_icon, size: 16, color: widget.color);
    if (widget.level != SyncLevel.busy) {
      return icon;
    }
    return RotationTransition(turns: _spin, child: icon);
  }
}
