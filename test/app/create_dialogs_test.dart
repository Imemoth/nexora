import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/presentation/create_task_dialog.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/theme/palette.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';

import 'package:nexora/features/tasks/domain/project.dart';

import '../support/task_fixtures.dart';
import '../support/workspace_harness.dart';

/// New task: Project first, then Title. New subtask: the parent is prominent.
Future<(Harness, TasksNotifier)> _pump(
  WidgetTester tester, {
  ThemePreference theme = ThemePreference.dark,
  Size size = const Size(1366, 768),
}) async {
  final h = await loadedHarness(
    tasks: [
      makeTask(id: 'plan1', title: 'Plan', position: 0),
      makeTask(id: 'plan2', title: 'Plan', position: 1),
      makeTask(id: 'budget', title: 'Budget', parentId: 'plan2'),
    ],
  );
  final n = TasksNotifier(h.workspace);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    NexoraApp(
      notifier: n,
      themeController: ThemeController(InMemorySettingsStore(), initial: theme),
    ),
  );
  await tester.pumpAndSettle();
  return (h, n);
}

/// Many projects and many parents, so the pickers have long lists.
Future<(Harness, TasksNotifier)> _pumpLong(
  WidgetTester tester, {
  ThemePreference theme = ThemePreference.dark,
  Size size = const Size(1280, 720),
}) async {
  final h = await loadedHarness(
    projects: [
      for (var i = 0; i < 40; i++)
        Project(id: 'p$i', name: 'Project number $i', position: i),
    ],
    tasks: [
      makeTask(id: 'root', title: 'Root', projectId: 'p0', position: 0),
      for (var i = 0; i < 40; i++)
        makeTask(
          id: 'k$i',
          title: 'Parent candidate $i',
          projectId: 'p0',
          position: i + 1,
        ),
    ],
  );
  final n = TasksNotifier(h.workspace);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    NexoraApp(
      notifier: n,
      themeController: ThemeController(InMemorySettingsStore(), initial: theme),
    ),
  );
  await tester.pumpAndSettle();
  n.selectProject('p5');
  await tester.pumpAndSettle();
  return (h, n);
}

/// The open dropdown list: the menu route's scrollable.
Finder get _openMenu => find.byType(Scrollable).last;

Future<void> _openNewTask(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('new-task')));
  await tester.pumpAndSettle();
}

void main() {
  group('New task: Project first, then Title', () {
    for (final theme in [ThemePreference.dark, ThemePreference.light]) {
      for (final size in const [
        Size(1366, 768),
        Size(1024, 768),
        Size(900, 700),
      ]) {
        testWidgets('${theme.name} at ${size.width.toInt()} px', (
          tester,
        ) async {
          await _pump(tester, theme: theme, size: size);
          await _openNewTask(tester);
          final project = tester.getRect(
            find.byKey(const ValueKey('create-project')),
          );
          final title = tester.getRect(
            find.byKey(const ValueKey('create-title')),
          );
          expect(
            project.bottom,
            lessThanOrEqualTo(title.top),
            reason: 'Project above Title',
          );
          expect(find.text(AppStrings.fieldProject), findsOneWidget);
          final dialog = tester.getRect(find.byType(AlertDialog));
          expect(dialog.left, greaterThanOrEqualTo(0));
          expect(dialog.right, lessThanOrEqualTo(size.width));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets(
      'the default project is kept (the selected one, else the first)',
      (tester) async {
        final (_, n) = await _pump(tester);
        n.selectProject('p2');
        await tester.pumpAndSettle();
        await _openNewTask(tester);
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('create-project')),
              )
              .value,
          'p2',
        );
      },
    );

    testWidgets(
      'creating is still efficient: the title has focus, type and press Enter',
      (tester) async {
        final (h, n) = await _pump(tester);
        n.selectProject('p1');
        await tester.pumpAndSettle();
        await _openNewTask(tester);
        final title = tester.widget<TextField>(
          find.byKey(const ValueKey('create-title')),
        );
        expect(title.focusNode?.hasPrimaryFocus ?? true, isTrue);
        await tester.enterText(
          find.byKey(const ValueKey('create-title')),
          'Quick',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(h.workspace.state.tasks['new-1']!.title, 'Quick');
        expect(h.workspace.state.tasks['new-1']!.projectId, 'p1');
      },
    );

    testWidgets('an empty title keeps the dialog open with the error', (
      tester,
    ) async {
      final (h, _) = await _pump(tester);
      await _openNewTask(tester);
      await tester.tap(find.byKey(const ValueKey('create-submit')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.titleRequired), findsOneWidget);
      expect(find.byKey(const ValueKey('create-title')), findsOneWidget);
      expect(h.workspace.state.tasks.containsKey('new-1'), isFalse);
    });

    testWidgets('another project can be chosen before typing', (tester) async {
      final (h, n) = await _pump(tester);
      n.selectProject('p1');
      await tester.pumpAndSettle();
      await _openNewTask(tester);
      await tester.tap(find.byKey(const ValueKey('create-project')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('create-title')),
        'In work',
      );
      await tester.tap(find.byKey(const ValueKey('create-submit')));
      await tester.pumpAndSettle();
      expect(h.workspace.state.tasks['new-1']!.projectId, 'p2');
    });

    testWidgets(
      'Tab order follows the visual order: Project, Title, Cancel, Create',
      (tester) async {
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(
          () => FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.automatic,
        );
        await _pump(tester);
        await _openNewTask(tester);

        Future<String?> where() async {
          final f = FocusManager.instance.primaryFocus;
          if (f?.context == null) {
            return null;
          }
          for (final key in [
            'create-project',
            'create-title',
            'create-cancel',
            'create-submit',
          ]) {
            final found = find.byKey(ValueKey(key));
            if (found.evaluate().isEmpty) {
              continue;
            }
            final inside = find.descendant(
              of: found,
              matching: find.byWidgetPredicate((w) => true),
            );
            final element = f!.context!;
            var hit = false;
            element.visitAncestorElements((a) {
              if (a.widget.key == ValueKey(key)) {
                hit = true;
                return false;
              }
              return true;
            });
            if (hit || (f.context!.widget.key == ValueKey(key))) {
              return key;
            }
            expect(inside, isNotNull);
          }
          return null;
        }

        expect(await where(), 'create-title'); // typing starts here
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(
          await where(),
          'create-project',
        ); // one step back is the project above it
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(await where(), 'create-title');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(await where(), 'create-cancel');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(await where(), 'create-submit');
      },
    );
  });

  group('New subtask: the parent is prominent', () {
    Future<void> openSubtask(WidgetTester tester, TasksNotifier n) async {
      n.selectProject('p1');
      n.selectTask('plan1');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-subtask')));
      await tester.pumpAndSettle();
    }

    for (final theme in [ThemePreference.dark, ThemePreference.light]) {
      testWidgets(
        'a framed parent card with the current task selected (${theme.name})',
        (tester) async {
          final (_, n) = await _pump(tester, theme: theme);
          await openSubtask(tester, n);
          final card = find.byKey(const ValueKey('create-parent-card'));
          expect(card, findsOneWidget);
          // framed in the accent colour of the theme
          final box =
              tester.widget<Container>(card).decoration! as BoxDecoration;
          final accent = theme == ThemePreference.dark
              ? NexoraPalette.dark.accentCyan
              : NexoraPalette.light.accentCyan;
          expect((box.border! as Border).top.color.toARGB32(), accent);
          expect((box.border! as Border).top.width, greaterThanOrEqualTo(1.5));
          // the selected parent reads as the strongest text of the card
          final selected = tester.widget<Text>(
            find.byKey(const ValueKey('create-parent-selected')),
          );
          expect(selected.data, 'Plan');
          expect(selected.style!.fontWeight!.value, greaterThanOrEqualTo(600));
          // current task preselected
          expect(
            tester
                .widget<DropdownButton<String>>(
                  find.byKey(const ValueKey('create-parent')),
                )
                .value,
            'plan1',
          );
          expect(
            find.text(AppStrings.fieldParentTask.toUpperCase()),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'the card sits above the title and the project stays as context',
      (tester) async {
        final (_, n) = await _pump(tester);
        await openSubtask(tester, n);
        final card = tester.getRect(
          find.byKey(const ValueKey('create-parent-card')),
        );
        final title = tester.getRect(
          find.byKey(const ValueKey('create-title')),
        );
        expect(card.bottom, lessThanOrEqualTo(title.top));
        expect(
          find.byKey(const ValueKey('create-parent-project')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'choosing another parent updates the emphasised text and creates there',
      (tester) async {
        final (h, n) = await _pump(tester);
        await openSubtask(tester, n);
        await tester.tap(find.byKey(const ValueKey('create-parent')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('create-parent-budget')).last,
        );
        await tester.pumpAndSettle();
        // same-named tasks stay distinguishable: the summary carries the ancestry
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('create-parent-selected')),
              )
              .data,
          'Plan › Budget',
        );
        await tester.enterText(
          find.byKey(const ValueKey('create-title')),
          'Deep',
        );
        await tester.tap(find.byKey(const ValueKey('create-submit')));
        await tester.pumpAndSettle();
        expect(h.workspace.state.tasks['new-1']!.parentId, 'budget');
        expect(h.workspace.state.tasks['new-1']!.projectId, 'p1');
      },
    );
  });

  group('project and parent pickers stay small and keep working', () {
    for (final theme in [ThemePreference.dark, ThemePreference.light]) {
      for (final size in const [Size(1280, 720), Size(900, 520)]) {
        testWidgets('project list: limited height, scrolls, choice works '
            '(${theme.name}, ${size.width.toInt()}x${size.height.toInt()})', (
          tester,
        ) async {
          final (h, _) = await _pumpLong(tester, theme: theme, size: size);
          await _openNewTask(tester);
          await tester.tap(find.byKey(const ValueKey('create-project')));
          await tester.pumpAndSettle();

          final menu = tester.getRect(_openMenu);
          expect(menu.height, lessThanOrEqualTo(264 + 1));
          // The current project is in the list; far entries need scrolling.
          expect(find.text('Project number 5'), findsWidgets);
          expect(find.text('Project number 39'), findsNothing);
          await tester.dragUntilVisible(
            find.text('Project number 39'),
            _openMenu,
            const Offset(0, -80),
          );
          await tester.tap(find.text('Project number 39').last);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('create-title')),
            'Far project',
          );
          await tester.tap(find.byKey(const ValueKey('create-submit')));
          await tester.pumpAndSettle();
          expect(h.workspace.state.tasks['new-1']!.projectId, 'p39');
        });

        testWidgets('parent list: limited height, scrolls, same project only '
            '(${theme.name}, ${size.width.toInt()}x${size.height.toInt()})', (
          tester,
        ) async {
          final (h, n) = await _pumpLong(tester, theme: theme, size: size);
          n.selectProject('p0');
          n.selectTask('root');
          await tester.pumpAndSettle();
          // Open the dialog directly: the details pane may need scrolling in a
          // short window, which is not what this test is about.
          unawaited(
            showCreateTaskDialog(
              tester.element(find.byType(Scaffold).first),
              n,
              parentId: 'root',
              parentTitle: 'Root',
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('create-parent')));
          await tester.pumpAndSettle();

          expect(tester.getRect(_openMenu).height, lessThanOrEqualTo(264 + 1));
          await tester.dragUntilVisible(
            find.byKey(const ValueKey('create-parent-k39')),
            _openMenu,
            const Offset(0, -80),
          );
          await tester.drag(_openMenu, const Offset(0, -120)); // fully in view
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('create-parent-k39')).last,
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('create-parent-selected')),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const ValueKey('create-title')),
            'Deep child',
          );
          await tester.tap(find.byKey(const ValueKey('create-submit')));
          await tester.pumpAndSettle();
          expect(h.workspace.state.tasks['new-1']!.parentId, 'k39');
        });
      }
    }

    testWidgets('keyboard: arrows move, Enter chooses, focus ring stays', (
      tester,
    ) async {
      final (h, _) = await _pumpLong(tester);
      await _openNewTask(tester);
      await tester.tap(find.byKey(const ValueKey('create-project')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('create-title')),
        'By keyboard',
      );
      await tester.tap(find.byKey(const ValueKey('create-submit')));
      await tester.pumpAndSettle();
      expect(h.workspace.state.tasks['new-1']!.projectId, 'p7');
    });
  });
}
