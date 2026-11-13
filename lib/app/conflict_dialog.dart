import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexora/app/conflict_panel.dart';
import 'package:nexora/features/sync/conflicts.dart';
import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

Future<void> showConflictDialog(BuildContext context, ConflictPanel panel) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ConflictDialog(panel: panel),
  );
}

/// Lists the unresolved conflicts, compares both versions side by side and sends
/// the user's decision. Nothing is shown as resolved before the engine reports
/// that the server confirmed it.
class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({required this.panel});

  final ConflictPanel panel;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  late List<ConflictView> _conflicts;
  String? _selected;
  final Set<String> _resolving = {};
  final Map<String, String> _messages = {};
  final Map<String, Map<String, MergePick>> _picks = {};
  String? _note;
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    _conflicts = widget.panel.load();
    _selected = _conflicts.isEmpty ? null : _conflicts.first.id;
    _subscription = widget.panel.changes.listen((_) => _reload());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _reload() {
    if (!mounted) {
      return;
    }
    final next = widget.panel.load();
    setState(() {
      _conflicts = next;
      if (!next.any((c) => c.id == _selected)) {
        _selected = next.isEmpty ? null : next.first.id;
      }
    });
  }

  ConflictView? get _current {
    for (final c in _conflicts) {
      if (c.id == _selected) {
        return c;
      }
    }
    return null;
  }

  Future<void> _decide(ConflictView view, ConflictChoice choice) async {
    if (_resolving.contains(view.id)) {
      return;
    }
    if (choice != ConflictChoice.recreateCopy) {
      final confirmed = await _confirm(view, choice);
      if (confirmed != true || !mounted) {
        return;
      }
    }
    setState(() {
      _resolving.add(view.id);
      _messages.remove(view.id);
      _note = null;
    });
    ConflictOutcome outcome;
    try {
      outcome = await widget.panel.resolve(
        view.id,
        choice,
        picks: choice == ConflictChoice.merge ? _picks[view.id] : null,
      );
    } on Object {
      outcome = const ConflictOutcome(ConflictOutcomeKind.failed);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _resolving.remove(view.id);
      if (outcome.ok) {
        _note = AppStrings.conflictsResolvedNote;
      } else {
        _messages[view.id] = _outcomeText(outcome);
      }
    });
    _reload();
  }

  String _outcomeText(ConflictOutcome o) => switch (o.kind) {
    ConflictOutcomeKind.offline => AppStrings.conflictOffline,
    ConflictOutcomeKind.authRequired => AppStrings.conflictAuth,
    ConflictOutcomeKind.deviceRevoked => AppStrings.conflictRevoked,
    ConflictOutcomeKind.alreadyDecidedElsewhere => AppStrings.conflictElsewhere,
    ConflictOutcomeKind.rejected => AppStrings.conflictRejected(o.code),
    ConflictOutcomeKind.unsupported => AppStrings.conflictUnsupported,
    ConflictOutcomeKind.inProgress => AppStrings.conflictBusy,
    ConflictOutcomeKind.notFound => AppStrings.conflictGone,
    ConflictOutcomeKind.failed => AppStrings.conflictFailed,
    ConflictOutcomeKind.resolved => '',
  };

  Future<bool?> _confirm(ConflictView view, ConflictChoice choice) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('conflict-confirm'),
        title: Text(AppStrings.conflictConfirmTitle(choice.name)),
        content: Text(AppStrings.conflictConfirmBody(choice.name, view.kind)),
        actions: [
          TextButton(
            key: const ValueKey('conflict-confirm-no'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.conflictCancelAction),
          ),
          FilledButton(
            key: const ValueKey('conflict-confirm-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.conflictConfirmAction),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Dialog(
      key: const ValueKey('conflict-dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.conflictTitleCount(_conflicts.length),
                      key: const ValueKey('conflict-title'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('conflict-close'),
                    tooltip: AppStrings.conflictCloseAction,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_note!, key: const ValueKey('conflict-note')),
                ),
              Expanded(
                child: current == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              AppStrings.conflictsNoneLeft,
                              key: ValueKey('conflict-none-left'),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              key: const ValueKey('conflict-done'),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(AppStrings.conflictCloseAction),
                            ),
                          ],
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 280, child: _list()),
                          const VerticalDivider(width: 24),
                          Expanded(child: _detail(current)),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.conflictsListHeader,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            key: const ValueKey('conflict-list'),
            children: [
              for (final c in _conflicts)
                ListTile(
                  key: ValueKey('conflict-item-${c.id}'),
                  dense: true,
                  selected: c.id == _selected,
                  title: Text(c.entityName, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      if (c.projectName != null) c.projectName!,
                      c.fields
                          .where((f) => f.differs)
                          .map((f) => f.label)
                          .join(', '),
                      _statusText(c),
                    ].where((t) => t.isNotEmpty).join(' · '),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => setState(() => _selected = c.id),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _statusText(ConflictView c) {
    if (_resolving.contains(c.id)) {
      return AppStrings.conflictStatusResolving;
    }
    return c.status == ConflictStatus.decidedElsewhere
        ? AppStrings.conflictStatusElsewhere
        : AppStrings.conflictStatusOpen;
  }

  Widget _detail(ConflictView view) {
    final busy = _resolving.contains(view.id);
    final picks = _picks.putIfAbsent(view.id, () => {});
    final mergeFields = view.mergeFields;
    final canMerge =
        view.choices.contains(ConflictChoice.merge) &&
        mergeFields.every((f) => picks.containsKey(f.field));
    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final choice in ConflictChoice.values)
          if (view.choices.contains(choice))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: choice == ConflictChoice.useServer
                        ? FilledButton.tonal(
                            key: ValueKey('choice-${choice.name}'),
                            onPressed: busy
                                ? null
                                : () => _decide(view, choice),
                            child: Text(_label(choice, view)),
                          )
                        : OutlinedButton(
                            key: ValueKey('choice-${choice.name}'),
                            onPressed:
                                busy ||
                                    (choice == ConflictChoice.merge &&
                                        !canMerge)
                                ? null
                                : () => _decide(view, choice),
                            child: Text(_label(choice, view)),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppStrings.conflictChoiceHelp(choice.name, view.kind),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        if (_messages[view.id] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _messages[view.id]!,
              key: const ValueKey('conflict-message'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
    return Column(
      key: const ValueKey('conflict-detail'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.entityName,
                  key: const ValueKey('conflict-entity'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (view.projectName != null)
                  Text(AppStrings.conflictProjectLine(view.projectName!)),
                const SizedBox(height: 4),
                Text(AppStrings.conflictKindSummary(view.kind, view.isTask)),
                const SizedBox(height: 4),
                Text(
                  _statusText(view),
                  key: const ValueKey('conflict-status'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 12),
                _table(view),
                if (view.choices.contains(ConflictChoice.merge)) ...[
                  const SizedBox(height: 12),
                  const Text(AppStrings.conflictPickIntro),
                  for (final f in mergeFields) _pickRow(view, f, picks, busy),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 20),
        actions,
      ],
    );
  }

  String _label(ConflictChoice choice, ConflictView view) =>
      AppStrings.conflictChoiceLabel(choice.name, view.kind);

  Widget _pickRow(
    ConflictView view,
    ConflictFieldView field,
    Map<String, MergePick> picks,
    bool busy,
  ) {
    return Row(
      children: [
        SizedBox(width: 140, child: Text(field.label)),
        for (final pick in MergePick.values)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChoiceChip(
              key: ValueKey('merge-pick-${field.field}-${pick.name}'),
              label: Text(
                pick == MergePick.local
                    ? AppStrings.conflictPickLocal
                    : AppStrings.conflictPickServer,
              ),
              selected: picks[field.field] == pick,
              onSelected: busy
                  ? null
                  : (selected) => setState(() {
                      if (selected) {
                        picks[field.field] = pick;
                      } else {
                        picks.remove(field.field);
                      }
                    }),
            ),
          ),
      ],
    );
  }

  Widget _table(ConflictView view) {
    final scheme = Theme.of(context).colorScheme;
    final header = Theme.of(context).textTheme.labelLarge;
    return Table(
      key: const ValueKey('conflict-table'),
      columnWidths: const {
        0: FixedColumnWidth(120),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: scheme.outlineVariant),
      ),
      children: [
        TableRow(
          children: [
            _cell(Text(AppStrings.conflictFieldColumn, style: header)),
            _cell(Text(AppStrings.conflictLocalColumn, style: header)),
            _cell(Text(AppStrings.conflictServerColumn, style: header)),
          ],
        ),
        for (final f in view.fields)
          TableRow(
            key: ValueKey('conflict-row-${f.field}'),
            decoration: f.differs
                ? BoxDecoration(color: scheme.tertiaryContainer)
                : null,
            children: [
              _cell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.label),
                    if (f.differs)
                      Text(
                        AppStrings.conflictDiffers,
                        key: ValueKey('conflict-differs-${f.field}'),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              _cell(_side(f.local, 'local-${f.field}')),
              _cell(_side(f.server, 'server-${f.field}')),
            ],
          ),
      ],
    );
  }

  Widget _cell(Widget child) =>
      Padding(padding: const EdgeInsets.all(8), child: child);

  Widget _side(ConflictSide side, String key) {
    final italic = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontStyle: FontStyle.italic);
    switch (side.state) {
      case ConflictSideState.value:
        return Text(side.text ?? '', key: ValueKey('conflict-$key'));
      case ConflictSideState.deleted:
        return Text(
          AppStrings.conflictSideDeleted,
          key: ValueKey('conflict-$key'),
          style: italic,
        );
      case ConflictSideState.unavailable:
        return Text(
          AppStrings.conflictSideUnavailable,
          key: ValueKey('conflict-$key'),
          style: italic,
        );
    }
  }
}
