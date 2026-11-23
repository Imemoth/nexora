import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';

import '../support/task_fixtures.dart';
import '../support/workspace_harness.dart';

/// A task found only through its Notes says so in its row. Which tasks match is
/// unchanged (see task_search_test.dart).
Future<TasksNotifier> _pump(
  WidgetTester tester, {
  double width = 1400,
  ThemePreference theme = ThemePreference.dark,
}) async {
  final longNotes =
      'Start of a very long note. ${'filler words ' * 30}litres of milk '
      '${'and more text ' * 30}';
  final h = await loadedHarness(
    tasks: [
      makeTask(id: 'notes', title: 'Groceries', notes: 'Two LITRES of milk'),
      makeTask(id: 'title', title: 'Litres tracker', notes: 'litres too'),
      makeTask(id: 'empty', title: 'No notes here', notes: ''),
      makeTask(id: 'long', title: 'Long one', notes: longNotes),
    ],
  );
  final n = TasksNotifier(h.workspace);
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    NexoraApp(
      notifier: n,
      themeController: ThemeController(InMemorySettingsStore(), initial: theme),
    ),
  );
  await tester.pumpAndSettle();
  return n;
}

Finder _line(String id) => find.byKey(ValueKey('notes-match-$id'));

void main() {
  for (final theme in [ThemePreference.dark, ThemePreference.light]) {
    testWidgets('only notes-only matches get an excerpt (${theme.name})', (
      tester,
    ) async {
      final n = await _pump(tester, theme: theme);
      n.search('litres');
      await tester.pumpAndSettle();

      expect(_line('notes'), findsOneWidget);
      expect(
        find.descendant(
          of: _line('notes'),
          matching: find.textContaining(
            AppStrings.notesMatchLabel,
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      expect(_line('title'), findsNothing, reason: 'the title explains it');
      expect(_line('empty'), findsNothing);
      expect(find.byKey(const ValueKey('row-empty')), findsNothing);
      // Case-insensitive: the notes keep their own spelling in the excerpt.
      final text = tester
          .widget<Tooltip>(
            find.descendant(of: _line('notes'), matching: find.byType(Tooltip)),
          )
          .message;
      expect(text, 'Two LITRES of milk');
    });
  }

  testWidgets('no query, no excerpt; clearing the search removes it', (
    tester,
  ) async {
    final n = await _pump(tester);
    expect(_line('notes'), findsNothing);
    n.search('milk');
    await tester.pumpAndSettle();
    expect(_line('notes'), findsOneWidget);
    n.search('');
    await tester.pumpAndSettle();
    expect(_line('notes'), findsNothing);
  });

  testWidgets('long notes stay on one line at a narrow width', (tester) async {
    final n = await _pump(tester, width: 920);
    n.search('litres of milk');
    await tester.pumpAndSettle();
    expect(_line('long'), findsOneWidget);
    final rect = tester.getRect(_line('long'));
    expect(rect.height, lessThan(30), reason: 'one line, not a paragraph');
    expect(rect.right, lessThanOrEqualTo(920));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the row announces the notes match to assistive technology', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final n = await _pump(tester);
    n.search('litres');
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('row-notes'))).label,
      contains('${AppStrings.notesMatchLabel}: Two LITRES of milk'),
    );
    handle.dispose();
  });
}
