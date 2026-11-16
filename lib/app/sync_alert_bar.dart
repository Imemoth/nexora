import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

import 'account_panel.dart';
import 'conflict_panel.dart';
import 'sync_card.dart';
import 'sync_panel.dart';
import 'sync_presentation.dart';

/// Full-width bar above the panes, only for the four critical sync states
/// (conflicts, sign-in needed, device removed, sync stopped). It cannot be
/// dismissed: it disappears when the state ends. The shell builds it only when
/// there is a sync panel, so the default build can never show it.
class SyncAlertBar extends StatelessWidget {
  const SyncAlertBar({
    super.key,
    required this.syncPanel,
    this.accountPanel,
    this.conflictPanel,
  });

  final SyncPanel syncPanel;
  final AccountPanel? accountPanel;
  final ConflictPanel? conflictPanel;

  @override
  Widget build(BuildContext context) {
    return PanelStreams(
      syncPanel: syncPanel,
      accountPanel: accountPanel,
      builder: (context, values) {
        final presentation = describeSync(
          values.status,
          signedIn: isSignedIn(accountPanel, values.account),
        );
        if (!presentation.showsBar) {
          return const SizedBox.shrink();
        }
        final c = NexoraColors.of(context);
        final fill = presentation.barSeverity == SyncBorder.warning
            ? c.severityWarning
            : c.severityCritical;
        final handler = syncActionHandler(
          context,
          presentation: presentation,
          status: values.status,
          syncPanel: syncPanel,
          accountPanel: accountPanel,
          conflictPanel: conflictPanel,
        );
        return Semantics(
          liveRegion: true,
          container: true,
          child: Container(
            key: const ValueKey('sync-alert-bar'),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: fill,
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 20, color: c.onSeverity),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    presentation.sentence,
                    key: const ValueKey('sync-alert-text'),
                    style: NexoraText.bodyStrong.copyWith(color: c.onSeverity),
                  ),
                ),
                if (presentation.action != SyncAction.none && handler != null)
                  SizedBox(
                    height: 34,
                    child: FilledButton(
                      key: ValueKey(
                        'alert-${syncActionKeyName(presentation.action)}',
                      ),
                      onPressed: handler,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.onSeverity,
                        foregroundColor: fill,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: Text(syncActionLabel(presentation.action)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
