import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

/// How serious a sync state is. Only [critical] takes the alert bar.
enum SyncLevel { ok, busy, info, warning, critical, off }

/// What a state asks the user to do.
enum SyncAction { none, syncNow, resolve, signIn }

/// Which token colours the card border.
enum SyncBorder { normal, warning, critical }

/// Everything the sync card, the alert bar and the dashboard show for one
/// [SyncStatus]. A pure value: no widgets, no engine calls.
final class SyncPresentation {
  const SyncPresentation({
    required this.level,
    required this.title,
    required this.sentence,
    required this.action,
    required this.border,
    required this.thickBorder,
    required this.showsBar,
    required this.barSeverity,
  });

  final SyncLevel level;

  /// The card title, for example "Up to date" or "2 conflicts".
  final String title;

  /// The existing sentence. Empty when the card hides it (Up to date,
  /// Synchronizing).
  final String sentence;
  final SyncAction action;
  final SyncBorder border;
  final bool thickBorder;

  /// True for the four critical states that take the alert bar.
  final bool showsBar;

  /// The fill of the alert bar when [showsBar] is set.
  final SyncBorder barSeverity;
}

/// Maps a status to its presentation. Precedence is the one of
/// `SyncStatusBar.describe`: the phase first, then conflicts, refused changes
/// and pending changes.
///
/// [signedIn] is false for a local workspace or after sign-out; that is the
/// "Local only" row, whatever the engine phase says.
SyncPresentation describeSync(SyncStatus status, {required bool signedIn}) {
  if (status.phase == SyncPhase.disabled) {
    return _local();
  }
  switch (status.phase) {
    case SyncPhase.disabled:
      return _local();
    case SyncPhase.syncing:
      return const SyncPresentation(
        level: SyncLevel.busy,
        title: AppStrings.syncTitleSyncing,
        sentence: '',
        action: SyncAction.none,
        border: SyncBorder.normal,
        thickBorder: false,
        showsBar: false,
        barSeverity: SyncBorder.normal,
      );
    case SyncPhase.retrying:
      return const SyncPresentation(
        level: SyncLevel.warning,
        title: AppStrings.syncTitleOffline,
        sentence: AppStrings.syncRetrying,
        action: SyncAction.syncNow,
        border: SyncBorder.warning,
        thickBorder: false,
        showsBar: false,
        barSeverity: SyncBorder.normal,
      );
    case SyncPhase.authRequired:
      return const SyncPresentation(
        level: SyncLevel.critical,
        title: AppStrings.syncTitleSignIn,
        sentence: AppStrings.syncSignInNeeded,
        action: SyncAction.signIn,
        border: SyncBorder.warning,
        thickBorder: true,
        showsBar: true,
        barSeverity: SyncBorder.warning,
      );
    case SyncPhase.deviceRevoked:
      return const SyncPresentation(
        level: SyncLevel.critical,
        title: AppStrings.syncTitleRevoked,
        sentence: AppStrings.syncDeviceRevoked,
        action: SyncAction.signIn,
        border: SyncBorder.critical,
        thickBorder: true,
        showsBar: true,
        barSeverity: SyncBorder.critical,
      );
    case SyncPhase.error:
      return const SyncPresentation(
        level: SyncLevel.critical,
        title: AppStrings.syncTitleError,
        sentence: AppStrings.syncError,
        action: SyncAction.syncNow,
        border: SyncBorder.critical,
        thickBorder: true,
        showsBar: true,
        barSeverity: SyncBorder.critical,
      );
    case SyncPhase.idle:
      if (!signedIn) {
        return _local();
      }
      if (status.openConflicts > 0) {
        return SyncPresentation(
          level: SyncLevel.critical,
          title: AppStrings.syncTitleConflicts(status.openConflicts),
          sentence: AppStrings.syncConflicts(status.openConflicts),
          action: SyncAction.resolve,
          border: SyncBorder.critical,
          thickBorder: true,
          showsBar: true,
          barSeverity: SyncBorder.critical,
        );
      }
      if (status.rejected > 0) {
        return SyncPresentation(
          level: SyncLevel.warning,
          title: AppStrings.syncTitleRejected(status.rejected),
          sentence: AppStrings.syncRejected(status.rejected),
          action: SyncAction.syncNow,
          border: SyncBorder.warning,
          thickBorder: false,
          showsBar: false,
          barSeverity: SyncBorder.normal,
        );
      }
      if (status.pending > 0) {
        return SyncPresentation(
          level: SyncLevel.info,
          title: AppStrings.syncTitlePending(status.pending),
          sentence: AppStrings.syncPending(status.pending),
          action: SyncAction.syncNow,
          border: SyncBorder.normal,
          thickBorder: false,
          showsBar: false,
          barSeverity: SyncBorder.normal,
        );
      }
      return const SyncPresentation(
        level: SyncLevel.ok,
        title: AppStrings.syncTitleUpToDate,
        sentence: '',
        action: SyncAction.syncNow,
        border: SyncBorder.normal,
        thickBorder: false,
        showsBar: false,
        barSeverity: SyncBorder.normal,
      );
  }
}

SyncPresentation _local() {
  return const SyncPresentation(
    level: SyncLevel.off,
    title: AppStrings.syncTitleLocal,
    sentence: AppStrings.accountLocalOnly,
    action: SyncAction.signIn,
    border: SyncBorder.normal,
    thickBorder: false,
    showsBar: false,
    barSeverity: SyncBorder.normal,
  );
}
