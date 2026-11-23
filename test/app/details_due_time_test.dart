import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';

import '../support/task_fixtures.dart';
import '../support/workspace_harness.dart';

/// Details pane: the whole due date is readable at every supported width and in
/// both themes; the optional time; the project above the title.
late Harness _h;

Future<TasksNotifier> _pump(
  WidgetTester tester, {
  required ThemePreference theme,
  double w = 1400,
  double h = 1000,
  bool timeSupported = true,
  List<Project>? projects,
  String selectId = 'd',
}) async {
  final harness = await loadedHarness(
    projects: projects ?? testProjects,
    dueTimeSupported: timeSupported,
    tasks: [
      makeTask(
        id: 'd',
        title: 'Dated',
        dueDate: const CalendarDate(2026, 11, 28),
      ),
      makeTask(
        id: 't',
        title: 'Timed',
        dueDate: const CalendarDate(2026, 11, 28),
        dueTime: const DueTime(17, 30),
      ),
      makeTask(id: 'u', title: 'Undated'),
    ],
  );
  _h = harness;
  final notifier = TasksNotifier(harness.workspace);
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    NexoraApp(
      notifier: notifier,
      themeController: ThemeController(InMemorySettingsStore(), initial: theme),
    ),
  );
  await tester.pumpAndSettle();
  notifier.selectTask(selectId);
  await tester.pumpAndSettle();
  return notifier;
}

bool _truncated(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  return paragraph.didExceedMaxLines;
}

void main() {
  for (final theme in [ThemePreference.dark, ThemePreference.light]) {
    // 1400: three panes (380 details). 1000: overlay (380). 900: the narrowest
    // width that still opens the overlay.
    for (final width in [1400.0, 1100.0, 1000.0, 900.0]) {
      testWidgets(
        'the full date, including the day, shows at ${width.toInt()} px (${theme.name})',
        (tester) async {
          await _pump(tester, theme: theme, w: width);
          final date = find.descendant(
            of: find.byKey(const ValueKey('due-date-button')),
            matching: find.text('2026-11-28'),
          );
          expect(date, findsOneWidget);
          expect(_truncated(tester, date), isFalse, reason: 'no ellipsis');
          // The button is wide enough for the whole value.
          final button = tester.getSize(
            find.byKey(const ValueKey('due-date-button')),
          );
          expect(button.width, greaterThan(200));
        },
      );
    }
  }

  testWidgets('a long date still fits at 150 % text scale', (tester) async {
    final harness = await loadedHarness(
      tasks: [
        makeTask(
          id: 'd',
          dueDate: const CalendarDate(2026, 11, 28),
          dueTime: const DueTime(17, 30),
        ),
      ],
    );
    final notifier = TasksNotifier(harness.workspace);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NexoraApp(notifier: notifier, textScaler: const TextScaler.linear(1.5)),
    );
    await tester.pumpAndSettle();
    notifier.selectTask('d');
    await tester.pumpAndSettle();
    final date = find.descendant(
      of: find.byKey(const ValueKey('due-date-button')),
      matching: find.text('2026-11-28'),
    );
    expect(_truncated(tester, date), isFalse);
    expect(tester.takeException(), isNull);
  });

  group('the optional time', () {
    testWidgets('a date-only task shows "No time" and offers to add one', (
      tester,
    ) async {
      final notifier = await _pump(tester, theme: ThemePreference.dark);
      expect(find.text(AppStrings.noDueTime), findsOneWidget);
      expect(find.byKey(const ValueKey('due-time-clear')), findsNothing);
      expect(notifier.state.draft!.dueTime, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('due-time-button')),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('a timed task shows its time and Remove time keeps the date', (
      tester,
    ) async {
      final notifier = await _pump(
        tester,
        theme: ThemePreference.light,
        selectId: 't',
      );
      expect(find.text('17:30'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('due-time-clear')));
      await tester.pumpAndSettle();

      expect(notifier.state.draft!.dueTime, isNull);
      expect(notifier.state.draft!.dueDate, const CalendarDate(2026, 11, 28));
      expect(notifier.state.draft!.isDirty, isTrue);
      expect(find.text(AppStrings.noDueTime), findsOneWidget);
    });

    testWidgets('clearing the date also clears the time and says so', (
      tester,
    ) async {
      final notifier = await _pump(
        tester,
        theme: ThemePreference.dark,
        selectId: 't',
      );
      expect(find.textContaining(AppStrings.clearDueDateHelp), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('due-date-clear')));
      await tester.pumpAndSettle();

      expect(notifier.state.draft!.dueDate, isNull);
      expect(notifier.state.draft!.dueTime, isNull);
      expect(find.text(AppStrings.dueTimeNeedsDate), findsOneWidget);
    });

    testWidgets('without a date the time cannot be set', (tester) async {
      await _pump(tester, theme: ThemePreference.dark, selectId: 'u');
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('due-time-button')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text(AppStrings.dueTimeNeedsDate), findsOneWidget);
    });

    testWidgets('picking a time puts it in the draft, dirty, not saved', (
      tester,
    ) async {
      final notifier = await _pump(tester, theme: ThemePreference.dark);
      await tester.tap(find.byKey(const ValueKey('due-time-button')));
      await tester.pumpAndSettle();
      // The picker opens in text-entry mode: type 07:45.
      final fields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.first, '7');
      await tester.enterText(fields.last, '45');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(notifier.state.draft!.dueTime, const DueTime(7, 45));
      expect(notifier.state.draft!.isDirty, isTrue);
      expect(notifier.state.tasks['d']!.dueTime, isNull); // not saved yet
    });

    testWidgets('Save stores the time and the task row shows it', (
      tester,
    ) async {
      final notifier = await _pump(
        tester,
        theme: ThemePreference.dark,
        selectId: 'u',
      );
      notifier.editDraft(dueDate: const CalendarDate(2026, 12, 2));
      notifier.editDraft(dueTime: const DueTime(9, 5));
      await tester.pumpAndSettle();
      await notifier.saveDraft();
      await tester.pumpAndSettle();

      expect(notifier.state.tasks['u']!.dueTime, const DueTime(9, 5));
      expect(
        find.textContaining('Wed 2 Dec · 09:05'),
        findsWidgets,
      ); // list row
    });

    testWidgets('in a synchronized workspace the time is off with the reason', (
      tester,
    ) async {
      final notifier = await _pump(
        tester,
        theme: ThemePreference.dark,
        timeSupported: false,
      );
      expect(find.text(AppStrings.dueTimeLocalOnly), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('due-time-button')),
            )
            .onPressed,
        isNull,
      );
      // The workspace refuses a time even if something asks for one.
      notifier.editDraft(dueTime: const DueTime(1, 0));
      expect(notifier.state.draft!.dueTime, isNull);
    });
  });

  group('hierarchy', () {
    testWidgets('the project name sits above the task title', (tester) async {
      await _pump(tester, theme: ThemePreference.dark);
      final project = tester.getTopLeft(
        find.byKey(const ValueKey('project-readonly')),
      );
      final title = tester.getTopLeft(find.byKey(const ValueKey('title-d')));
      expect(project.dy, lessThan(title.dy));
      expect(find.text('Home'), findsWidgets);
    });

    testWidgets(
      'a long project name is ellipsized with the full value available',
      (tester) async {
        const longName =
            'A very long project name that cannot possibly fit on one line of the details pane';
        await _pump(
          tester,
          theme: ThemePreference.light,
          projects: const [Project(id: 'p1', name: longName, position: 0)],
        );
        final name = find.descendant(
          of: find.byKey(const ValueKey('project-readonly')),
          matching: find.text(longName),
        );
        expect(_truncated(tester, name), isTrue);
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(
            of: find.byKey(const ValueKey('project-readonly')),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.message, longName);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the save bar stays pinned while the body scrolls', (
      tester,
    ) async {
      await _pump(tester, theme: ThemePreference.dark, h: 500);
      final before = tester.getTopLeft(find.byKey(const ValueKey('save-bar')));
      await tester.drag(
        find.descendant(
          of: find.byKey(const ValueKey('details-pane')),
          matching: find.byType(ListView),
        ),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const ValueKey('save-bar'))), before);
    });

    testWidgets('Save and Revert still follow the dirty state', (tester) async {
      final notifier = await _pump(tester, theme: ThemePreference.dark);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('save')))
            .onPressed,
        isNull,
      );
      notifier.editDraft(dueTime: const DueTime(10, 0));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('save')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('revert')));
      await tester.pumpAndSettle();
      expect(notifier.state.draft!.isDirty, isFalse);
    });
  });

  group('incoming change while editing, in the UI', () {
    testWidgets('a banner tells the user; their edit stays in the field', (
      tester,
    ) async {
      final notifier = await _pump(tester, theme: ThemePreference.dark);
      notifier.editDraft(title: 'My edit');
      await tester.pumpAndSettle();
      // An incoming change is applied through the workspace.
      // (The repository behind the harness is shared with the workspace.)
      await _h.repository.saveTask(
        notifier.state.tasks['d']!.copyWith(notes: 'Remote notes'),
      );
      await _h.workspace.refresh();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('incoming-banner')), findsOneWidget);
      expect(find.text(AppStrings.incomingUpdatedTitle), findsOneWidget);
      expect(find.text('My edit'), findsOneWidget);
      expect(find.text('Remote notes'), findsOneWidget);
    });
  });
}
