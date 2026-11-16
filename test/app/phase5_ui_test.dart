import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/account_panel.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/app/sync_panel.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';

import '../support/task_fixtures.dart';
import '../support/workspace_harness.dart';

Future<void> _size(
  WidgetTester tester, {
  double w = 1400,
  double h = 900,
}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<TasksNotifier> _pumpApp(
  WidgetTester tester, {
  SyncPanel? sync,
  AccountPanel? account,
  ThemeController? theme,
  List<dynamic>? tasks,
  double w = 1400,
  double h = 900,
}) async {
  final harness = await loadedHarness(tasks: (tasks ?? sampleTasks()).cast());
  final notifier = TasksNotifier(harness.workspace);
  await _size(tester, w: w, h: h);
  await tester.pumpWidget(
    NexoraApp(
      notifier: notifier,
      syncPanel: sync,
      accountPanel: account,
      themeController: theme,
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

SyncPanel _sync(StreamController<SyncStatus> c, SyncStatus initial) =>
    SyncPanel(initial: initial, statuses: c.stream, syncNow: () async {});

AccountPanel _account(AccountPhase phase, {String? email}) => AccountPanel(
  initial: AccountView(phase: phase, email: email),
  views: const Stream<AccountView>.empty(),
  signIn: (e, p) async => SignInOutcome.success,
  signOut: () async {},
);

void main() {
  group('synchronization off (the default build)', () {
    testWidgets('the card says Local only with no action and no alert bar', (
      tester,
    ) async {
      await _pumpApp(tester, theme: ThemeController(InMemorySettingsStore()));
      expect(find.text(AppStrings.syncTitleLocal), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-now')), findsNothing);
      expect(find.byKey(const ValueKey('sign-in')), findsNothing);
      expect(find.byKey(const ValueKey('sync-alert-bar')), findsNothing);
      expect(find.text(AppStrings.accountLocalShort), findsOneWidget);
    });

    testWidgets('the menu holds only Theme and Keyboard shortcuts', (
      tester,
    ) async {
      await _pumpApp(tester, theme: ThemeController(InMemorySettingsStore()));
      await tester.tap(find.byKey(const ValueKey('account-row')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('theme-selector')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-shortcuts')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-sign-in')), findsNothing);
      expect(find.byKey(const ValueKey('sign-out')), findsNothing);
      expect(find.byKey(const ValueKey('bar-import')), findsNothing);
    });
  });

  group('the alert bar', () {
    const critical = [
      SyncStatus(phase: SyncPhase.idle, openConflicts: 1),
      SyncStatus(phase: SyncPhase.authRequired),
      SyncStatus(phase: SyncPhase.deviceRevoked),
      SyncStatus(phase: SyncPhase.error),
    ];
    const calm = [
      SyncStatus(phase: SyncPhase.idle),
      SyncStatus(phase: SyncPhase.syncing),
      SyncStatus(phase: SyncPhase.idle, pending: 2),
      SyncStatus(phase: SyncPhase.retrying),
      SyncStatus(phase: SyncPhase.idle, rejected: 1),
      SyncStatus(phase: SyncPhase.disabled),
    ];

    testWidgets('appears for the four critical states only', (tester) async {
      final controller = StreamController<SyncStatus>.broadcast();
      addTearDown(controller.close);
      await _pumpApp(
        tester,
        sync: _sync(controller, calm.first),
        account: _account(AccountPhase.signedIn, email: 'me@example.test'),
      );
      for (final status in calm) {
        controller.add(status);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('sync-alert-bar')),
          findsNothing,
          reason: '${status.phase} must not show the bar',
        );
      }
      for (final status in critical) {
        controller.add(status);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('sync-alert-bar')),
          findsOneWidget,
          reason: '${status.phase} must show the bar',
        );
      }
    });

    testWidgets('is absent without a sync panel', (tester) async {
      await _pumpApp(tester);
      expect(find.byKey(const ValueKey('sync-alert-bar')), findsNothing);
    });

    testWidgets('cannot be dismissed and goes away when the state ends', (
      tester,
    ) async {
      final controller = StreamController<SyncStatus>.broadcast();
      addTearDown(controller.close);
      await _pumpApp(
        tester,
        sync: _sync(controller, critical.first),
        account: _account(AccountPhase.signedIn, email: 'me@example.test'),
      );
      expect(find.byKey(const ValueKey('sync-alert-bar')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sync-alert-bar')),
          matching: find.byIcon(Icons.close),
        ),
        findsNothing,
      );
      controller.add(const SyncStatus(phase: SyncPhase.idle));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sync-alert-bar')), findsNothing);
    });
  });

  group('the save bar', () {
    testWidgets('is disabled when clean, enabled when dirty', (tester) async {
      final notifier = await _pumpApp(tester);
      notifier.selectTask('a');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('saved-indicator')), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const ValueKey('save')))
            .onPressed,
        isNull,
      );
      notifier.editDraft(title: 'Alpha 2');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dirty-indicator')), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const ValueKey('save')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('stays visible when the body scrolls', (tester) async {
      final notifier = await _pumpApp(tester, h: 500);
      notifier.selectTask('a');
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(find.byKey(const ValueKey('save-bar'))).dy;
      await tester.drag(
        find.descendant(
          of: find.byKey(const ValueKey('details-pane')),
          matching: find.byType(ListView),
        ),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const ValueKey('save-bar'))).dy, top);
      expect(find.byKey(const ValueKey('save')), findsOneWidget);
    });
  });

  group('the gate', () {
    testWidgets('entering the dashboard with a dirty draft opens it', (
      tester,
    ) async {
      final notifier = await _pumpApp(tester);
      notifier.selectTask('a');
      notifier.editDraft(title: 'changed');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-dashboard')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gate-save')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gate-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dashboard-pane')), findsNothing);
    });

    testWidgets('choosing Sign out with a dirty draft opens it', (
      tester,
    ) async {
      var signedOut = 0;
      final panel = AccountPanel(
        initial: const AccountView(
          phase: AccountPhase.signedIn,
          email: 'me@example.test',
        ),
        views: const Stream<AccountView>.empty(),
        signIn: (e, p) async => SignInOutcome.success,
        signOut: () async => signedOut++,
      );
      final notifier = await _pumpApp(tester, account: panel);
      notifier.selectTask('a');
      notifier.editDraft(title: 'changed');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-out')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gate-save')), findsOneWidget);
      expect(signedOut, 0);
      // Discard releases the sign-out.
      await tester.tap(find.byKey(const ValueKey('gate-discard')));
      await tester.pumpAndSettle();
      expect(signedOut, 1);
    });

    testWidgets('selecting a subtask row with a dirty draft opens it', (
      tester,
    ) async {
      final notifier = await _pumpApp(tester);
      notifier.selectTask('parent');
      notifier.editDraft(title: 'changed');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('subtask-child')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gate-save')), findsOneWidget);
      expect(notifier.state.selectedTaskId, 'parent');
    });
  });

  group('the focus ring', () {
    BorderSide ringOf(WidgetTester tester, String id) {
      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(ValueKey('row-$id')),
              matching: find.byType(Material),
            )
            .first,
      );
      return (material.shape! as RoundedRectangleBorder).side;
    }

    testWidgets('is on the selected row while the list has focus', (
      tester,
    ) async {
      await _pumpApp(tester);
      await tester.tap(find.byKey(const ValueKey('row-a')));
      await tester.pumpAndSettle();
      final side = ringOf(tester, 'a');
      expect(side.width, 2);
      expect(side.color, NexoraColors.dark.accentCyan);
    });

    testWidgets('rows are not focus targets', (tester) async {
      await _pumpApp(tester);
      final ink = tester.widget<InkWell>(find.byKey(const ValueKey('row-a')));
      expect(ink.canRequestFocus, isFalse);
    });
  });

  group('context text', () {
    testWidgets('a smart view names the project of every row', (tester) async {
      final demo = buildDemoData(testToday);
      final harness = await loadedHarness(
        tasks: demo.tasks,
        projects: demo.projects,
      );
      final notifier = TasksNotifier(harness.workspace);
      await _size(tester);
      await tester.pumpWidget(NexoraApp(notifier: notifier));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('context-home-utility')))
            .data,
        'Home',
      );
    });

    testWidgets('a child shows its parent only when the parent row is hidden', (
      tester,
    ) async {
      final notifier = await _pumpApp(
        tester,
        tasks: [
          makeTask(id: 'p', title: 'Release'),
          makeTask(id: 'k', parentId: 'p', title: 'Notes draft'),
        ],
      );
      notifier.selectProject('p1');
      await tester.pumpAndSettle();
      // Both rows shown (parent expanded): no parent label on the child.
      notifier.toggleExpanded('p');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('context-k')), findsNothing);
      // A search that hides the parent names it.
      notifier.search('Notes');
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('context-k'))).data,
        'Release',
      );
    });
  });

  group('the theme', () {
    testWidgets('changing it leaves selection and draft untouched', (
      tester,
    ) async {
      final store = InMemorySettingsStore();
      final controller = ThemeController(store);
      final notifier = await _pumpApp(tester, theme: controller);
      notifier.selectTask('a');
      notifier.editDraft(title: 'in progress');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('account-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.themeLight));
      await tester.pumpAndSettle();

      expect(controller.preference, ThemePreference.light);
      expect(await store.loadThemePreference(), ThemePreference.light);
      expect(notifier.state.selectedTaskId, 'a');
      expect(notifier.state.draft!.title, 'in progress');
      expect(notifier.state.pending, isNull);
    });
  });

  group('status filter, quick add and delete in the window', () {
    testWidgets('a chip filters the list and shows counts', (tester) async {
      await _pumpApp(
        tester,
        tasks: [
          makeTask(id: 'a', title: 'Open one'),
          makeTask(id: 'b', title: 'Done one', status: TaskStatus.done),
        ],
      );
      expect(find.byKey(const ValueKey('row-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-b')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-a')), findsNothing);
      expect(find.byKey(const ValueKey('row-b')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-a')), findsOneWidget);
    });

    testWidgets('quick add creates a root task and keeps typing possible', (
      tester,
    ) async {
      final notifier = await _pumpApp(tester);
      notifier.selectProject('p1');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick-add')),
        'Wrap gifts',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final created = notifier.state.tasks.values.where(
        (t) => t.title == 'Wrap gifts',
      );
      expect(created, hasLength(1));
      expect(created.single.parentId, isNull);
      expect(created.single.projectId, 'p1');
    });

    testWidgets('quick add refuses an empty title with the usual message', (
      tester,
    ) async {
      await _pumpApp(tester);
      await tester.tap(find.byKey(const ValueKey('quick-add')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-add-error')), findsOneWidget);
      expect(find.text(AppStrings.titleRequired), findsOneWidget);
    });

    testWidgets('Delete task asks first; Cancel changes nothing', (
      tester,
    ) async {
      final notifier = await _pumpApp(tester);
      notifier.selectTask('parent');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('delete-task')));
      await tester.tap(find.byKey(const ValueKey('delete-task')));
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.deleteTaskBody(1)),
        findsOneWidget,
        reason: 'the dialog counts the subtasks that go too',
      );
      await tester.tap(find.byKey(const ValueKey('delete-cancel')));
      await tester.pumpAndSettle();
      expect(notifier.state.tasks.containsKey('parent'), isTrue);
    });

    testWidgets('Delete removes the task and its subtasks', (tester) async {
      final notifier = await _pumpApp(tester);
      notifier.selectTask('parent');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('delete-task')));
      await tester.tap(find.byKey(const ValueKey('delete-task')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();
      expect(notifier.state.tasks.containsKey('parent'), isFalse);
      expect(notifier.state.tasks.containsKey('child'), isFalse);
      expect(find.text(AppStrings.taskDeleted), findsOneWidget);
    });

    testWidgets('the last project has Delete project disabled', (tester) async {
      final harness = await loadedHarness(
        tasks: [makeTask(id: 'a')],
        projects: [testProjects.first],
      );
      final notifier = TasksNotifier(harness.workspace);
      await _size(tester);
      await tester.pumpWidget(NexoraApp(notifier: notifier));
      await tester.pumpAndSettle();
      notifier.selectProject('p1');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project-menu')));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<String>>(
        find.byKey(const ValueKey('delete-project')),
      );
      expect(item.enabled, isFalse);
    });
  });

  group('the dashboard', () {
    testWidgets('counts equal the sidebar counts and tiles navigate', (
      tester,
    ) async {
      final demo = buildDemoData(testToday);
      final harness = await loadedHarness(
        tasks: demo.tasks,
        projects: demo.projects,
      );
      final notifier = TasksNotifier(harness.workspace);
      await _size(tester);
      await tester.pumpWidget(NexoraApp(notifier: notifier));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-dashboard')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dashboard-pane')), findsOneWidget);
      // The details pane is hidden on the dashboard.
      expect(find.byKey(const ValueKey('details-pane')), findsNothing);
      for (final view in SmartView.values) {
        final label = AppStrings.smartViewLabel(view);
        expect(
          tester.widget<Text>(find.byKey(ValueKey('dash-count-$label'))).data,
          notifier.state.countFor(SmartViewSelection(view)).toString(),
          reason: '$label tile equals the sidebar count',
        );
      }
      await tester.tap(find.byKey(const ValueKey('dash-tile-overdue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dashboard-pane')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('list-title'))).data,
        'Overdue',
      );
    });
  });
}
