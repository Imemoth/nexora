import 'package:flutter/material.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

/// What the UI needs from the synchronization engine, and nothing else. The
/// application root receives this only when the feature flag is on and a
/// transport exists; by default it is null and no bar is shown.
final class SyncPanel {
  const SyncPanel({
    required this.initial,
    required this.statuses,
    required this.syncNow,
  });

  final SyncStatus initial;
  final Stream<SyncStatus> statuses;
  final Future<void> Function() syncNow;
}

/// A thin bar: the current state in plain words and a manual "Sync now".
class SyncStatusBar extends StatelessWidget {
  const SyncStatusBar({super.key, required this.panel});

  final SyncPanel panel;

  static String describe(SyncStatus s) {
    switch (s.phase) {
      case SyncPhase.disabled:
        return AppStrings.syncDisabled;
      case SyncPhase.syncing:
        return AppStrings.syncing;
      case SyncPhase.retrying:
        return AppStrings.syncRetrying;
      case SyncPhase.authRequired:
        return AppStrings.syncSignInNeeded;
      case SyncPhase.deviceRevoked:
        return AppStrings.syncDeviceRevoked;
      case SyncPhase.error:
        return AppStrings.syncError;
      case SyncPhase.idle:
        if (s.openConflicts > 0) {
          return AppStrings.syncConflicts(s.openConflicts);
        }
        if (s.rejected > 0) {
          return AppStrings.syncRejected(s.rejected);
        }
        if (s.pending > 0) {
          return AppStrings.syncPending(s.pending);
        }
        return AppStrings.syncUpToDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: panel.statuses,
      initialData: panel.initial,
      builder: (context, snapshot) {
        final status = snapshot.data ?? panel.initial;
        final busy = status.phase == SyncPhase.syncing;
        return Material(
          key: const ValueKey('sync-status-bar'),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    describe(status),
                    key: const ValueKey('sync-status-text'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  key: const ValueKey('sync-now'),
                  onPressed: busy ? null : panel.syncNow,
                  child: const Text(AppStrings.syncNowAction),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
