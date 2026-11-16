import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/account_actions.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../support/workspace_harness.dart';

void main() {
  Future<List<List<ImportChoiceView>>> pumpEmpty(
    WidgetTester tester, {
    ImportPreviewView? preview,
    ImportOutcomeView outcome = const ImportOutcomeView(
      ok: true,
      projectsCreated: 1,
      tasksImported: 2,
    ),
  }) async {
    final runs = <List<ImportChoiceView>>[];
    final harness = await loadedHarness(tasks: const [], projects: const []);
    final panel = ImportPanel(
      preview: () async =>
          preview ??
          const ImportPreviewView(
            candidates: [
              ImportCandidateView(
                id: 'lp1',
                name: 'Work',
                taskCount: 2,
                warnings: {ImportWarningView.sameNameExists},
              ),
            ],
            skippedLocalOnly: 3,
          ),
      destinations: () async => const [DestinationView('d1', 'Existing')],
      run: (choices) async {
        runs.add(choices);
        return outcome;
      },
    );
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      NexoraApp(notifier: TasksNotifier(harness.workspace), importPanel: panel),
    );
    await tester.pumpAndSettle();
    return runs;
  }

  testWidgets('an empty account shows the choice and creates nothing itself', (
    tester,
  ) async {
    await pumpEmpty(tester);
    expect(find.byKey(const ValueKey('empty-account')), findsOneWidget);
    expect(find.text(AppStrings.emptyAccountTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-import')), findsOneWidget);
  });

  testWidgets('New project creates a project and leaves the empty state', (
    tester,
  ) async {
    await pumpEmpty(tester);
    await tester.tap(find.byKey(const ValueKey('empty-new-project')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-project-name')),
      'Inbox',
    );
    await tester.tap(find.byKey(const ValueKey('new-project-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('empty-account')), findsNothing);
    expect(find.text('Inbox'), findsWidgets);
  });

  testWidgets('a blank project name is refused and the dialog stays', (
    tester,
  ) async {
    await pumpEmpty(tester);
    await tester.tap(find.byKey(const ValueKey('empty-new-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-project-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-project-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-account')), findsOneWidget);
  });

  testWidgets('import is preview first and runs only what was chosen', (
    tester,
  ) async {
    final runs = await pumpEmpty(tester);
    await tester.tap(find.byKey(const ValueKey('empty-import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-dialog')), findsOneWidget);
    expect(find.text(AppStrings.importSameName), findsOneWidget);
    expect(find.byKey(const ValueKey('import-skipped')), findsOneWidget);
    expect(runs, isEmpty);
    final run = tester.widget<FilledButton>(
      find.byKey(const ValueKey('import-run')),
    );
    expect(run.onPressed, isNull); // nothing chosen yet

    await tester.tap(find.byKey(const ValueKey('import-check-lp1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-run')));
    await tester.pumpAndSettle();
    expect(runs, hasLength(1));
    expect(runs.single.single.sourceProjectId, 'lp1');
    expect(runs.single.single.destinationProjectId, isNull);
    expect(find.byKey(const ValueKey('import-outcome')), findsOneWidget);
  });

  testWidgets('a failed import says nothing was changed', (tester) async {
    await pumpEmpty(
      tester,
      outcome: const ImportOutcomeView(ok: false, errorCode: 'write_failed'),
    );
    await tester.tap(find.byKey(const ValueKey('empty-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-check-lp1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-run')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.importFailed), findsOneWidget);
  });

  testWidgets('nothing to import is stated plainly', (tester) async {
    await pumpEmpty(tester, preview: const ImportPreviewView(candidates: []));
    await tester.tap(find.byKey(const ValueKey('empty-import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-empty')), findsOneWidget);
  });

  group('due times in the import preview', () {
    testWidgets(
      'without server support the preview warns that times are NOT kept',
      (tester) async {
        await pumpEmpty(
          tester,
          preview: const ImportPreviewView(
            dueTimesTransferable: false,
            candidates: [
              ImportCandidateView(
                id: 'lp1',
                name: 'Work',
                taskCount: 3,
                dueTimeCount: 2,
                warnings: {},
              ),
            ],
          ),
        );
        await tester.tap(find.byKey(const ValueKey('empty-import')));
        await tester.pumpAndSettle();
        final warning = find.byKey(const ValueKey('import-due-time-warning'));
        expect(warning, findsOneWidget);
        expect(
          tester.widget<Text>(warning).data,
          AppStrings.importDueTimesLost(2),
        );
        expect(tester.widget<Text>(warning).data, contains('date only'));
        expect(tester.widget<Text>(warning).data, contains('not kept'));
        // never implies the times are preserved
        expect(
          find.byKey(const ValueKey('import-due-time-kept')),
          findsNothing,
        );
        // the project row says how many lose their time
        expect(
          find.textContaining(AppStrings.importCandidateDueTimesDropped(2)),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'with server support the preview says times are kept and shows no warning',
      (tester) async {
        await pumpEmpty(
          tester,
          preview: const ImportPreviewView(
            dueTimesTransferable: true,
            candidates: [
              ImportCandidateView(
                id: 'lp1',
                name: 'Work',
                taskCount: 3,
                dueTimeCount: 2,
                warnings: {},
              ),
            ],
          ),
        );
        await tester.tap(find.byKey(const ValueKey('empty-import')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('import-due-time-kept')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('import-due-time-warning')),
          findsNothing,
        );
      },
    );

    testWidgets('projects without due times show neither note', (tester) async {
      await pumpEmpty(
        tester,
        preview: const ImportPreviewView(
          candidates: [
            ImportCandidateView(
              id: 'lp1',
              name: 'Work',
              taskCount: 3,
              warnings: {},
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('empty-import')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('import-due-time-warning')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('import-due-time-kept')), findsNothing);
    });

    testWidgets(
      'the import is still explicit: nothing runs until the user confirms',
      (tester) async {
        final runs = await pumpEmpty(
          tester,
          preview: const ImportPreviewView(
            candidates: [
              ImportCandidateView(
                id: 'lp1',
                name: 'Work',
                taskCount: 1,
                dueTimeCount: 1,
                warnings: {},
              ),
            ],
          ),
        );
        await tester.tap(find.byKey(const ValueKey('empty-import')));
        await tester.pumpAndSettle();
        expect(runs, isEmpty);
      },
    );
  });
}
