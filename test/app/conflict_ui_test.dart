import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/conflict_panel.dart';
import 'package:nexora/app/sync_panel.dart';
import 'package:nexora/features/sync/conflicts.dart';
import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

ConflictView _field({
  String id = 'c1',
  String name = 'CONFLICT-B',
  String local = 'CONFLICT-B',
  String server = 'CONFLICT-A',
  Set<ConflictChoice>? choices,
  ConflictStatus status = ConflictStatus.open,
  String kind = 'field',
  List<ConflictFieldView>? fields,
}) => ConflictView(
  id: id,
  entityType: 'task',
  entityName: name,
  projectName: 'Home',
  kind: kind,
  status: status,
  choices: choices ?? {ConflictChoice.useServer, ConflictChoice.keepLocal},
  fields:
      fields ??
      [
        ConflictFieldView(
          field: 'title',
          label: 'Title',
          local: ConflictSide.value(local),
          server: ConflictSide.value(server),
          differs: local != server,
          canPick: true,
        ),
      ],
);

final class _Fake {
  _Fake(List<ConflictView> initial) : conflicts = List.of(initial);

  List<ConflictView> conflicts;
  final StreamController<void> changes = StreamController<void>.broadcast();
  final List<(String, ConflictChoice, Map<String, MergePick>?)> calls = [];
  Future<ConflictOutcome> Function(String id, ConflictChoice c)? handler;

  ConflictPanel get panel => ConflictPanel(
    load: () => List.of(conflicts),
    changes: changes.stream,
    resolve: (id, choice, {picks}) async {
      calls.add((id, choice, picks));
      final outcome =
          await (handler?.call(id, choice) ??
              Future.value(
                const ConflictOutcome(ConflictOutcomeKind.resolved),
              ));
      if (outcome.ok) {
        conflicts = conflicts.where((c) => c.id != id).toList();
        changes.add(null);
      }
      return outcome;
    },
  );
}

void main() {
  late StreamController<SyncStatus> statuses;
  var syncs = 0;

  setUp(() {
    statuses = StreamController<SyncStatus>.broadcast();
    syncs = 0;
  });
  tearDown(() => statuses.close());

  Future<void> pumpBar(
    WidgetTester tester,
    _Fake fake, {
    int openConflicts = 1,
    bool withPanel = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SyncStatusBar(
              panel: SyncPanel(
                initial: SyncStatus(
                  phase: SyncPhase.idle,
                  openConflicts: openConflicts,
                ),
                statuses: statuses.stream,
                syncNow: () async => syncs++,
              ),
              conflictPanel: withPanel ? fake.panel : null,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('sync-conflicts')));
    await tester.pumpAndSettle();
  }

  group('the indicator', () {
    testWidgets(
      'is a clickable control with the count; Sync now stays available',
      (tester) async {
        final fake = _Fake([_field(), _field(id: 'c2', name: 'Second')]);
        await pumpBar(tester, fake, openConflicts: 2);

        expect(find.byKey(const ValueKey('sync-conflicts')), findsOneWidget);
        expect(find.text('2 conflicts need your decision'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('sync-now')))
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('sync-now')));
        expect(syncs, 1);

        await openDialog(tester);
        expect(find.byKey(const ValueKey('conflict-dialog')), findsOneWidget);
        expect(find.byKey(const ValueKey('conflict-title')), findsOneWidget);
      },
    );

    testWidgets('is reachable and activated from the keyboard', (tester) async {
      final fake = _Fake([_field()]);
      await pumpBar(tester, fake);

      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        if (find
            .byKey(const ValueKey('conflict-dialog'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(find.byKey(const ValueKey('conflict-dialog')), findsOneWidget);
    });

    testWidgets('is absent when there are no conflicts', (tester) async {
      await pumpBar(tester, _Fake([]), openConflicts: 0);
      expect(find.byKey(const ValueKey('sync-conflicts')), findsNothing);
    });

    testWidgets('without a panel the conflicts are only mentioned as text', (
      tester,
    ) async {
      await pumpBar(tester, _Fake([]), openConflicts: 1, withPanel: false);
      expect(find.byKey(const ValueKey('sync-conflicts')), findsNothing);
      expect(find.text('1 conflict needs your decision'), findsOneWidget);
    });
  });

  group('the list and the comparison', () {
    testWidgets('lists every conflict and switches the detail on selection', (
      tester,
    ) async {
      final fake = _Fake([
        _field(),
        _field(
          id: 'c2',
          name: 'Buy milk',
          local: 'Buy oat milk',
          server: 'Buy milk 2l',
        ),
      ]);
      await pumpBar(tester, fake, openConflicts: 2);
      await openDialog(tester);

      expect(find.byKey(const ValueKey('conflict-item-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('conflict-item-c2')), findsOneWidget);
      expect(find.text('Resolve conflicts (2)'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('conflict-entity'))).data,
        'CONFLICT-B',
      );

      await tester.tap(find.byKey(const ValueKey('conflict-item-c2')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('conflict-entity'))).data,
        'Buy milk',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('conflict-local-title')))
            .data,
        'Buy oat milk',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('conflict-server-title')))
            .data,
        'Buy milk 2l',
      );
    });

    testWidgets(
      'shows both versions side by side, highlights differences, no raw JSON',
      (tester) async {
        final fake = _Fake([
          _field(
            fields: [
              const ConflictFieldView(
                field: 'title',
                label: 'Title',
                local: ConflictSide.value('Mine'),
                server: ConflictSide.value('Theirs'),
                differs: true,
                canPick: true,
              ),
              const ConflictFieldView(
                field: 'notes',
                label: 'Notes',
                local: ConflictSide.value('same'),
                server: ConflictSide.value('same'),
                differs: false,
              ),
              const ConflictFieldView(
                field: 'due_date',
                label: 'Due date',
                local: ConflictSide.deleted(),
                server: ConflictSide.unavailable(),
                differs: true,
              ),
            ],
          ),
        ]);
        await pumpBar(tester, fake);
        await openDialog(tester);

        expect(find.text(AppStrings.conflictLocalColumn), findsOneWidget);
        expect(find.text(AppStrings.conflictServerColumn), findsOneWidget);
        expect(
          find.byKey(const ValueKey('conflict-differs-title')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('conflict-differs-notes')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('conflict-differs-due_date')),
          findsOneWidget,
        );
        expect(find.text(AppStrings.conflictSideDeleted), findsOneWidget);
        expect(find.text(AppStrings.conflictSideUnavailable), findsOneWidget);
        expect(find.textContaining('{'), findsNothing);
        expect(find.textContaining('_json'), findsNothing);
      },
    );

    testWidgets('only the valid choices are offered', (tester) async {
      final fake = _Fake([_field()]);
      await pumpBar(tester, fake);
      await openDialog(tester);

      expect(find.byKey(const ValueKey('choice-useServer')), findsOneWidget);
      expect(find.byKey(const ValueKey('choice-keepLocal')), findsOneWidget);
      expect(find.byKey(const ValueKey('choice-merge')), findsNothing);
      expect(find.byKey(const ValueKey('choice-recreateCopy')), findsNothing);
    });

    testWidgets('a decision made on another device is labelled as such', (
      tester,
    ) async {
      final fake = _Fake([_field(status: ConflictStatus.decidedElsewhere)]);
      await pumpBar(tester, fake);
      await openDialog(tester);

      expect(
        tester.widget<Text>(find.byKey(const ValueKey('conflict-status'))).data,
        AppStrings.conflictStatusElsewhere,
      );
    });
  });

  group('deciding', () {
    testWidgets(
      'use server asks for confirmation, then resolves and the conflict disappears',
      (tester) async {
        final fake = _Fake([_field()]);
        await pumpBar(tester, fake);
        await openDialog(tester);

        await tester.tap(find.byKey(const ValueKey('choice-useServer')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('conflict-confirm')), findsOneWidget);
        expect(fake.calls, isEmpty); // nothing sent before the confirmation

        await tester.tap(find.byKey(const ValueKey('conflict-confirm-yes')));
        await tester.pumpAndSettle();

        expect(fake.calls.single.$1, 'c1');
        expect(fake.calls.single.$2, ConflictChoice.useServer);
        expect(find.byKey(const ValueKey('conflict-item-c1')), findsNothing);
        expect(
          find.byKey(const ValueKey('conflict-none-left')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'cancelling the confirmation sends nothing and keeps the conflict',
      (tester) async {
        final fake = _Fake([_field()]);
        await pumpBar(tester, fake);
        await openDialog(tester);

        await tester.tap(find.byKey(const ValueKey('choice-keepLocal')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('conflict-confirm-no')));
        await tester.pumpAndSettle();

        expect(fake.calls, isEmpty);
        expect(find.byKey(const ValueKey('conflict-item-c1')), findsOneWidget);
      },
    );

    testWidgets('keep local resolves after confirmation', (tester) async {
      final fake = _Fake([_field()]);
      await pumpBar(tester, fake);
      await openDialog(tester);

      await tester.tap(find.byKey(const ValueKey('choice-keepLocal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conflict-confirm-yes')));
      await tester.pumpAndSettle();

      expect(fake.calls.single.$2, ConflictChoice.keepLocal);
    });

    testWidgets('merge needs a pick for every field, then sends the picks', (
      tester,
    ) async {
      final fake = _Fake([
        _field(
          choices: {
            ConflictChoice.useServer,
            ConflictChoice.keepLocal,
            ConflictChoice.merge,
          },
          fields: const [
            ConflictFieldView(
              field: 'title',
              label: 'Title',
              local: ConflictSide.value('A'),
              server: ConflictSide.value('B'),
              differs: true,
              canPick: true,
            ),
            ConflictFieldView(
              field: 'notes',
              label: 'Notes',
              local: ConflictSide.value('x'),
              server: ConflictSide.value('y'),
              differs: true,
              canPick: true,
            ),
          ],
        ),
      ]);
      await pumpBar(tester, fake);
      await openDialog(tester);

      Finder merge() => find.byKey(const ValueKey('choice-merge'));
      expect(tester.widget<OutlinedButton>(merge()).onPressed, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('merge-pick-title-local')),
      );
      await tester.tap(find.byKey(const ValueKey('merge-pick-title-local')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<OutlinedButton>(merge()).onPressed,
        isNull,
      ); // still one open
      await tester.ensureVisible(
        find.byKey(const ValueKey('merge-pick-notes-server')),
      );
      await tester.tap(find.byKey(const ValueKey('merge-pick-notes-server')));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(merge()).onPressed, isNotNull);

      await tester.tap(merge());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conflict-confirm-yes')));
      await tester.pumpAndSettle();

      final call = fake.calls.single;
      expect(call.$2, ConflictChoice.merge);
      expect(call.$3, {'title': MergePick.local, 'notes': MergePick.server});
    });

    testWidgets(
      'recreate as copy needs no confirmation (nothing is discarded)',
      (tester) async {
        final fake = _Fake([
          _field(
            kind: 'edit_deleted',
            choices: {ConflictChoice.useServer, ConflictChoice.recreateCopy},
            fields: const [
              ConflictFieldView(
                field: '_item',
                label: 'Task',
                local: ConflictSide.value('Changed by you'),
                server: ConflictSide.deleted(),
                differs: true,
              ),
            ],
          ),
        ]);
        await pumpBar(tester, fake);
        await openDialog(tester);

        expect(find.text('Accept the deletion'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('choice-recreateCopy')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('conflict-confirm')), findsNothing);
        expect(fake.calls.single.$2, ConflictChoice.recreateCopy);
      },
    );

    testWidgets(
      'the status shows the decision being sent and blocks a second click',
      (tester) async {
        final fake = _Fake([_field()]);
        final gate = Completer<ConflictOutcome>();
        fake.handler = (id, choice) => gate.future;
        await pumpBar(tester, fake);
        await openDialog(tester);

        await tester.tap(find.byKey(const ValueKey('choice-useServer')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('conflict-confirm-yes')));
        await tester.pump();

        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('conflict-status')))
              .data,
          AppStrings.conflictStatusResolving,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('choice-useServer')),
              )
              .onPressed,
          isNull,
        );
        gate.complete(const ConflictOutcome(ConflictOutcomeKind.resolved));
        await tester.pumpAndSettle();
        expect(fake.calls, hasLength(1));
      },
    );
  });

  group('failures', () {
    Future<void> decide(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conflict-confirm-yes')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'offline: an actionable message, the conflict stays, a retry succeeds',
      (tester) async {
        final fake = _Fake([_field()]);
        var failing = true;
        fake.handler = (id, choice) async => failing
            ? const ConflictOutcome(ConflictOutcomeKind.offline)
            : const ConflictOutcome(ConflictOutcomeKind.resolved);
        await pumpBar(tester, fake);
        await openDialog(tester);

        await decide(tester, 'choice-keepLocal');
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('conflict-message')))
              .data,
          AppStrings.conflictOffline,
        );
        expect(find.byKey(const ValueKey('conflict-item-c1')), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('choice-keepLocal')),
              )
              .onPressed,
          isNotNull,
        ); // retry possible

        failing = false;
        await decide(tester, 'choice-keepLocal');
        expect(find.byKey(const ValueKey('conflict-message')), findsNothing);
        expect(
          find.byKey(const ValueKey('conflict-none-left')),
          findsOneWidget,
        );
        expect(fake.calls, hasLength(2));
      },
    );

    testWidgets(
      'every other failure has its own message and never a success state',
      (tester) async {
        final cases = {
          ConflictOutcomeKind.authRequired: AppStrings.conflictAuth,
          ConflictOutcomeKind.deviceRevoked: AppStrings.conflictRevoked,
          ConflictOutcomeKind.alreadyDecidedElsewhere:
              AppStrings.conflictElsewhere,
          ConflictOutcomeKind.unsupported: AppStrings.conflictUnsupported,
          ConflictOutcomeKind.inProgress: AppStrings.conflictBusy,
          ConflictOutcomeKind.notFound: AppStrings.conflictGone,
          ConflictOutcomeKind.failed: AppStrings.conflictFailed,
        };
        for (final entry in cases.entries) {
          final fake = _Fake([_field()]);
          fake.handler = (id, choice) async => ConflictOutcome(entry.key);
          await pumpBar(tester, fake);
          await openDialog(tester);
          await decide(tester, 'choice-useServer');
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('conflict-message')))
                .data,
            entry.value,
            reason: '${entry.key}',
          );
          expect(find.byKey(const ValueKey('conflict-note')), findsNothing);
          await tester.tap(find.byKey(const ValueKey('conflict-close')));
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets('a server rejection names its code', (tester) async {
      final fake = _Fake([_field()]);
      fake.handler = (id, choice) async => const ConflictOutcome(
        ConflictOutcomeKind.rejected,
        'strategy_not_allowed',
      );
      await pumpBar(tester, fake);
      await openDialog(tester);
      await decide(tester, 'choice-useServer');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('conflict-message')))
            .data,
        AppStrings.conflictRejected('strategy_not_allowed'),
      );
    });

    testWidgets('an exception from the panel is contained', (tester) async {
      final fake = _Fake([_field()]);
      fake.handler = (id, choice) async => throw StateError('boom');
      await pumpBar(tester, fake);
      await openDialog(tester);
      await decide(tester, 'choice-useServer');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('conflict-message')))
            .data,
        AppStrings.conflictFailed,
      );
    });
  });

  group('automatic refresh', () {
    testWidgets(
      'a conflict resolved elsewhere disappears when the list changes',
      (tester) async {
        final fake = _Fake([_field(), _field(id: 'c2', name: 'Second')]);
        await pumpBar(tester, fake, openConflicts: 2);
        await openDialog(tester);
        expect(find.byKey(const ValueKey('conflict-item-c1')), findsOneWidget);

        fake.conflicts = fake.conflicts.where((c) => c.id != 'c1').toList();
        fake.changes.add(null);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('conflict-item-c1')), findsNothing);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('conflict-entity')))
              .data,
          'Second',
        ); // selection moved to the next conflict
      },
    );
  });
}
