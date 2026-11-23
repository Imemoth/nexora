import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/sync_presentation.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

SyncPresentation _d(SyncStatus s, {bool signedIn = true}) =>
    describeSync(s, signedIn: signedIn);

void main() {
  group('describeSync: the ten rows of the mapping', () {
    test('1. idle, nothing pending: Up to date, Sync now, no bar', () {
      final p = _d(const SyncStatus(phase: SyncPhase.idle));
      expect(p.level, SyncLevel.ok);
      expect(p.title, AppStrings.syncTitleUpToDate);
      expect(p.sentence, isEmpty);
      expect(p.action, SyncAction.syncNow);
      expect(p.border, SyncBorder.normal);
      expect(p.showsBar, isFalse);
    });

    test('2. syncing: Synchronizing, no action, no bar', () {
      final p = _d(const SyncStatus(phase: SyncPhase.syncing));
      expect(p.level, SyncLevel.busy);
      expect(p.title, AppStrings.syncTitleSyncing);
      expect(p.action, SyncAction.none);
      expect(p.showsBar, isFalse);
    });

    test('3. idle with pending changes: N changes waiting', () {
      final p = _d(const SyncStatus(phase: SyncPhase.idle, pending: 3));
      expect(p.level, SyncLevel.info);
      expect(p.title, AppStrings.syncTitlePending(3));
      expect(p.sentence, AppStrings.syncPending(3));
      expect(p.action, SyncAction.syncNow);
      expect(p.showsBar, isFalse);
    });

    test('4. retrying: Offline, warning border, no bar', () {
      final p = _d(const SyncStatus(phase: SyncPhase.retrying));
      expect(p.level, SyncLevel.warning);
      expect(p.title, AppStrings.syncTitleOffline);
      expect(p.sentence, AppStrings.syncRetrying);
      expect(p.border, SyncBorder.warning);
      expect(p.thickBorder, isFalse);
      expect(p.showsBar, isFalse);
    });

    test('5. idle with refused changes: N changes refused, no bar', () {
      final p = _d(const SyncStatus(phase: SyncPhase.idle, rejected: 2));
      expect(p.level, SyncLevel.warning);
      expect(p.title, AppStrings.syncTitleRejected(2));
      expect(p.sentence, AppStrings.syncRejected(2));
      expect(p.border, SyncBorder.warning);
      expect(p.showsBar, isFalse);
    });

    test('6. idle with conflicts: N conflicts, Resolve, critical bar', () {
      final p = _d(const SyncStatus(phase: SyncPhase.idle, openConflicts: 2));
      expect(p.level, SyncLevel.critical);
      expect(p.title, AppStrings.syncTitleConflicts(2));
      expect(p.sentence, AppStrings.syncConflicts(2));
      expect(p.action, SyncAction.resolve);
      expect(p.border, SyncBorder.critical);
      expect(p.thickBorder, isTrue);
      expect(p.showsBar, isTrue);
      expect(p.barSeverity, SyncBorder.critical);
    });

    test('7. authRequired: Sign in needed, warning bar', () {
      final p = _d(const SyncStatus(phase: SyncPhase.authRequired));
      expect(p.level, SyncLevel.critical);
      expect(p.title, AppStrings.syncTitleSignIn);
      expect(p.sentence, AppStrings.syncSignInNeeded);
      expect(p.action, SyncAction.signIn);
      expect(p.border, SyncBorder.warning);
      expect(p.thickBorder, isTrue);
      expect(p.showsBar, isTrue);
      expect(p.barSeverity, SyncBorder.warning);
    });

    test('8. deviceRevoked: Device removed, critical bar', () {
      final p = _d(const SyncStatus(phase: SyncPhase.deviceRevoked));
      expect(p.title, AppStrings.syncTitleRevoked);
      expect(p.sentence, AppStrings.syncDeviceRevoked);
      expect(p.action, SyncAction.signIn);
      expect(p.border, SyncBorder.critical);
      expect(p.showsBar, isTrue);
      expect(p.barSeverity, SyncBorder.critical);
    });

    test('9. error: Sync stopped, Sync now, critical bar', () {
      final p = _d(const SyncStatus(phase: SyncPhase.error));
      expect(p.title, AppStrings.syncTitleError);
      expect(p.sentence, AppStrings.syncError);
      expect(p.action, SyncAction.syncNow);
      expect(p.border, SyncBorder.critical);
      expect(p.showsBar, isTrue);
    });

    test('10. disabled or signed out: Local only, Sign in, no bar', () {
      final disabled = _d(const SyncStatus(phase: SyncPhase.disabled));
      expect(disabled.level, SyncLevel.off);
      expect(disabled.title, AppStrings.syncTitleLocal);
      expect(disabled.sentence, AppStrings.accountLocalOnly);
      expect(disabled.action, SyncAction.signIn);
      expect(disabled.showsBar, isFalse);

      final signedOut = _d(
        const SyncStatus(phase: SyncPhase.idle, openConflicts: 3),
        signedIn: false,
      );
      expect(signedOut.title, AppStrings.syncTitleLocal);
      expect(signedOut.showsBar, isFalse);
    });
  });

  group('precedence: phase over conflicts over refused over pending', () {
    test('a phase wins over everything else', () {
      final p = _d(
        const SyncStatus(
          phase: SyncPhase.retrying,
          openConflicts: 1,
          rejected: 1,
          pending: 1,
        ),
      );
      expect(p.title, AppStrings.syncTitleOffline);
    });

    test('conflicts beat refused and pending', () {
      final p = _d(
        const SyncStatus(
          phase: SyncPhase.idle,
          openConflicts: 1,
          rejected: 2,
          pending: 3,
        ),
      );
      expect(p.title, AppStrings.syncTitleConflicts(1));
    });

    test('refused beats pending', () {
      final p = _d(
        const SyncStatus(phase: SyncPhase.idle, rejected: 2, pending: 3),
      );
      expect(p.title, AppStrings.syncTitleRejected(2));
    });
  });

  test('exactly the four critical states take the alert bar', () {
    final bars = [
      for (final s in [
        const SyncStatus(phase: SyncPhase.idle),
        const SyncStatus(phase: SyncPhase.syncing),
        const SyncStatus(phase: SyncPhase.idle, pending: 1),
        const SyncStatus(phase: SyncPhase.retrying),
        const SyncStatus(phase: SyncPhase.idle, rejected: 1),
        const SyncStatus(phase: SyncPhase.idle, openConflicts: 1),
        const SyncStatus(phase: SyncPhase.authRequired),
        const SyncStatus(phase: SyncPhase.deviceRevoked),
        const SyncStatus(phase: SyncPhase.error),
        const SyncStatus(phase: SyncPhase.disabled),
      ])
        _d(s).showsBar,
    ];
    expect(bars.where((shown) => shown), hasLength(4));
  });
}
