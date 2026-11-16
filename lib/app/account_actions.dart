import 'package:flutter/material.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';

enum ImportWarningView { alreadyImported, sameNameExists }

final class ImportCandidateView {
  const ImportCandidateView({
    required this.id,
    required this.name,
    required this.taskCount,
    required this.warnings,
    this.sameNameProjectId,
    this.dueTimeCount = 0,
  });

  /// Tasks of this project that have a due time.
  final int dueTimeCount;

  final String id;
  final String name;
  final int taskCount;
  final Set<ImportWarningView> warnings;
  final String? sameNameProjectId;
}

final class ImportPreviewView {
  const ImportPreviewView({
    required this.candidates,
    this.skippedLocalOnly = 0,
    this.skippedUnclassified = 0,
    this.skippedDeleted = 0,
    this.dueTimesTransferable = false,
  });

  /// False while the account's server cannot store due times: the import then
  /// keeps dates and drops times, and the preview says so.
  final bool dueTimesTransferable;

  final List<ImportCandidateView> candidates;
  final int skippedLocalOnly;
  final int skippedUnclassified;
  final int skippedDeleted;
}

final class DestinationView {
  const DestinationView(this.id, this.name);

  final String id;
  final String name;
}

final class ImportChoiceView {
  const ImportChoiceView({
    required this.sourceProjectId,
    this.destinationProjectId,
    this.allowDuplicate = false,
  });

  final String sourceProjectId;
  final String? destinationProjectId;
  final bool allowDuplicate;
}

final class ImportOutcomeView {
  const ImportOutcomeView({
    required this.ok,
    this.projectsCreated = 0,
    this.tasksImported = 0,
    this.tasksSkipped = 0,
    this.backupFile,
    this.errorCode,
  });

  final bool ok;
  final int projectsCreated;
  final int tasksImported;
  final int tasksSkipped;
  final String? backupFile;
  final String? errorCode;
}

/// What the UI needs for the manual import (provided only for a signed-in account).
final class ImportPanel {
  const ImportPanel({
    required this.preview,
    required this.destinations,
    required this.run,
  });

  final Future<ImportPreviewView> Function() preview;
  final Future<List<DestinationView>> Function() destinations;
  final Future<ImportOutcomeView> Function(List<ImportChoiceView>) run;
}

Future<void> showNewProjectDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _NewProjectDialog(),
  );
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final notifier = TasksScope.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await notifier.createProject(_name.text);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        navigator.pop();
      case Err(:final error):
        setState(() {
          _busy = false;
          _error = AppStrings.errorMessage(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('new-project-dialog'),
      title: const Text(AppStrings.newProjectTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('new-project-name'),
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              onSubmitted: (_) => _create(),
              decoration: const InputDecoration(
                labelText: AppStrings.projectNameLabel,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  key: const ValueKey('new-project-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancelAction),
        ),
        FilledButton(
          key: const ValueKey('new-project-create'),
          onPressed: _busy ? null : _create,
          child: const Text(AppStrings.createAction),
        ),
      ],
    );
  }
}

Future<void> showImportDialog(BuildContext context, ImportPanel panel) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ImportDialog(panel: panel),
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.panel});

  final ImportPanel panel;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  ImportPreviewView? _preview;

  bool get _dueTimesKept => _preview?.dueTimesTransferable ?? false;
  List<DestinationView> _destinations = const [];
  final Set<String> _selected = {};
  final Map<String, String?> _destination = {};
  final Set<String> _again = {};
  bool _busy = true;
  ImportOutcomeView? _outcome;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final preview = await widget.panel.preview();
      final destinations = await widget.panel.destinations();
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = preview;
        _destinations = destinations;
        _busy = false;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _outcome = const ImportOutcomeView(ok: false, errorCode: 'preview');
        _busy = false;
      });
    }
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    final choices = [
      for (final id in _selected)
        ImportChoiceView(
          sourceProjectId: id,
          destinationProjectId: _destination[id],
          allowDuplicate: _again.contains(id),
        ),
    ];
    final outcome = await widget.panel.run(choices);
    if (!mounted) {
      return;
    }
    setState(() {
      _outcome = outcome;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _outcome;
    final preview = _preview;
    return AlertDialog(
      key: const ValueKey('import-dialog'),
      title: const Text(AppStrings.importTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (outcome != null)
                Text(
                  outcome.ok
                      ? AppStrings.importDone(
                          outcome.projectsCreated,
                          outcome.tasksImported,
                          outcome.tasksSkipped,
                        )
                      : AppStrings.importFailed,
                  key: const ValueKey('import-outcome'),
                )
              else if (preview == null)
                const Text(AppStrings.importWorking)
              else ...[
                const Text(AppStrings.importIntro),
                const SizedBox(height: 12),
                if (preview.candidates.isEmpty)
                  const Text(
                    AppStrings.importNothingToOffer,
                    key: ValueKey('import-empty'),
                  ),
                for (final c in preview.candidates) _row(c),
                if (!preview.dueTimesTransferable &&
                    preview.candidates.any((c) => c.dueTimeCount > 0))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      AppStrings.importDueTimesLost(
                        preview.candidates.fold(
                          0,
                          (sum, c) => sum + c.dueTimeCount,
                        ),
                      ),
                      key: const ValueKey('import-due-time-warning'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                if (preview.dueTimesTransferable &&
                    preview.candidates.any((c) => c.dueTimeCount > 0))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      AppStrings.importDueTimesKept,
                      key: ValueKey('import-due-time-kept'),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.importSkippedNote(
                    preview.skippedLocalOnly,
                    preview.skippedUnclassified,
                    preview.skippedDeleted,
                  ),
                  key: const ValueKey('import-skipped'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (outcome?.ok == true && outcome?.backupFile != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${AppStrings.importBackupNote} ${outcome!.backupFile}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('import-close'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(
            outcome == null ? AppStrings.cancelAction : AppStrings.closeDetails,
          ),
        ),
        if (outcome == null)
          FilledButton(
            key: const ValueKey('import-run'),
            onPressed: _busy || _selected.isEmpty ? null : _run,
            child: const Text(AppStrings.importAction),
          ),
      ],
    );
  }

  Widget _row(ImportCandidateView c) {
    final blocked = c.warnings.contains(ImportWarningView.alreadyImported);
    final selected = _selected.contains(c.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            key: ValueKey('import-check-${c.id}'),
            value: selected,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              '${c.name} · ${AppStrings.importTaskCount(c.taskCount)}',
            ),
            subtitle: Text(
              [
                if (blocked) AppStrings.importAlreadyDone,
                if (c.warnings.contains(ImportWarningView.sameNameExists))
                  AppStrings.importSameName,
                if (c.dueTimeCount > 0 && !_dueTimesKept)
                  AppStrings.importCandidateDueTimesDropped(c.dueTimeCount),
              ].join('. '),
            ),
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    if (v == true) {
                      _selected.add(c.id);
                    } else {
                      _selected.remove(c.id);
                    }
                  }),
          ),
          if (selected)
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(AppStrings.importDestinationLabel),
                  DropdownButton<String?>(
                    key: ValueKey('import-destination-${c.id}'),
                    value: _destination[c.id],
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(AppStrings.importNewProject),
                      ),
                      for (final d in _destinations)
                        DropdownMenuItem<String?>(
                          value: d.id,
                          child: Text(d.name),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _destination[c.id] = v),
                  ),
                  if (blocked)
                    FilterChip(
                      key: ValueKey('import-again-${c.id}'),
                      label: const Text(AppStrings.importAgainAnyway),
                      selected: _again.contains(c.id),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _again.add(c.id);
                        } else {
                          _again.remove(c.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown over an empty account: nothing is created or imported automatically.
class EmptyAccountNotice extends StatelessWidget {
  const EmptyAccountNotice({super.key, this.importPanel});

  final ImportPanel? importPanel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        key: const ValueKey('empty-account'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.emptyAccountTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(AppStrings.emptyAccountBody),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton(
                      key: const ValueKey('empty-new-project'),
                      onPressed: () => showNewProjectDialog(context),
                      child: const Text(AppStrings.newProjectAction),
                    ),
                    if (importPanel != null)
                      OutlinedButton(
                        key: const ValueKey('empty-import'),
                        onPressed: () =>
                            showImportDialog(context, importPanel!),
                        child: const Text(AppStrings.importLocalAction),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
