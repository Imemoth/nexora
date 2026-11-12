import 'dart:io';

import 'package:nexora/core/ids/id_generator.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_database.dart';
import 'snapshot_digest.dart';
import 'sqlite_task_repository.dart';

/// Why a candidate needs the user's attention before it is imported.
enum ImportWarning {
  /// This project was imported into this account before (the mapping is stored).
  alreadyImported,

  /// The account already has a project with the same name.
  sameNameExists,
}

/// What the import never offers, and why.
final class ImportSkipped {
  const ImportSkipped({
    this.localOnly = 0,
    this.unclassified = 0,
    this.deleted = 0,
    this.orphaned = 0,
  });

  /// Demo and other local-only records: never synchronized, never imported.
  final int localOnly;

  /// Records of an old database whose origin is unknown: never imported
  /// automatically (reclassifying them is a separate, manual owner action).
  final int unclassified;
  final int deleted;

  /// Tasks whose parent is not importable: listed, not moved (the tree is kept).
  final int orphaned;
}

final class ImportCandidate {
  const ImportCandidate({
    required this.project,
    required this.tasks,
    required this.warnings,
    this.alreadyImportedAs,
    this.sameNameProjectId,
  });

  final Project project;

  /// The live synchronized tasks of the project, parents before children.
  final List<Task> tasks;
  final Set<ImportWarning> warnings;
  final String? alreadyImportedAs;
  final String? sameNameProjectId;
}

final class ImportPreview {
  const ImportPreview({
    required this.sourceOwnerId,
    required this.candidates,
    required this.skipped,
  });

  final String sourceOwnerId;
  final List<ImportCandidate> candidates;
  final ImportSkipped skipped;

  bool get isEmpty => candidates.isEmpty;
}

/// One decision of the user. Nothing is imported without one.
final class ImportChoice {
  const ImportChoice({
    required this.sourceProjectId,
    this.destinationProjectId,
    this.allowDuplicate = false,
  });

  final String sourceProjectId;

  /// An existing project of the account to merge into, or null for a new project.
  final String? destinationProjectId;

  /// Import even though the project was imported before. Tasks that duplicate an
  /// existing task of the destination are still skipped.
  final bool allowDuplicate;
}

final class ImportResult {
  const ImportResult({
    required this.projectsCreated,
    required this.tasksImported,
    required this.tasksSkippedDuplicate,
    required this.backupFile,
  });

  final int projectsCreated;
  final int tasksImported;
  final int tasksSkippedDuplicate;

  /// The verified copy of the account database taken before the import. It is
  /// kept; it is never deleted automatically.
  final String backupFile;
}

final class ImportException implements Exception {
  const ImportException(this.code, [this.detail]);

  /// Stable code: `no_source`, `same_file`, `nothing_selected`, `unknown_source`,
  /// `unknown_destination`, `blocked_duplicate`, `backup_failed`, `write_failed`.
  final String code;
  final String? detail;

  @override
  String toString() =>
      'ImportException($code${detail == null ? '' : ': $detail'})';
}

/// Manual, preview-first import of the local workspace's projects and tasks into
/// the signed-in account's database.
///
/// Guarantees (each covered by tests):
/// * The local file is only read. Nothing in it changes.
/// * Only live, synchronized (class S) records are offered. Local-only and
///   unclassified records are counted and never moved.
/// * Every imported record gets a new identifier (old identifiers need not be
///   valid server identifiers); the old-to-new mapping is stored in the account
///   database (`meta` keys `import_map:...`), so nothing is lost and a repeat is
///   detected.
/// * The task hierarchy, notes, status, priority, due dates and order are kept.
/// * A verified backup of the account database is written first; the write itself
///   is one SQLite transaction (all or nothing). A failure changes nothing.
/// * Pending work of the account is untouched; imported records are queued like
///   any new record and are sent by the normal synchronization.
final class LocalImportService {
  LocalImportService({
    required this.sourcePath,
    required this.target,
    required this.repository,
    required IdGenerator ids,
    DateTime Function()? now,
    this.backupDirectory,
    this.beforeCommit,
  }) : _ids = ids,
       _now = now ?? (() => DateTime.now().toUtc());

  final String sourcePath;
  final LocalDatabase target;
  final SqliteTaskRepository repository;
  final String? backupDirectory;

  /// Test seam: runs inside the transaction before COMMIT; throwing rolls back.
  final void Function()? beforeCommit;
  final IdGenerator _ids;
  final DateTime Function() _now;

  static String _mapKey(String sourceOwner, String kind, String id) =>
      'import_map:$sourceOwner:$kind:$id';

  Future<ImportPreview> preview() async {
    final source = _openSource();
    try {
      return await _preview(source);
    } finally {
      source.close();
    }
  }

  LocalDatabase _openSource() {
    if (!File(sourcePath).existsSync()) {
      throw const ImportException('no_source', 'there is no local workspace');
    }
    if (File(sourcePath).absolute.path == File(target.filePath).absolute.path) {
      throw const ImportException('same_file');
    }
    return LocalDatabase.open(sourcePath);
  }

  Future<ImportPreview> _preview(LocalDatabase source) async {
    final reader = SqliteTaskRepository(source, ownerId: 'import-reader');
    final projects = await reader.loadProjects();
    final tasks = await reader.loadTasks();
    final projectScope = {
      for (final r in source.raw.select(
        'SELECT id, sync_scope FROM projects WHERE deleted_at IS NULL',
      ))
        r['id'] as String: r['sync_scope'] as String,
    };
    final taskScope = {
      for (final r in source.raw.select(
        'SELECT id, sync_scope FROM tasks WHERE deleted_at IS NULL',
      ))
        r['id'] as String: r['sync_scope'] as String,
    };
    final deleted =
        (source.raw
                .select(
                  'SELECT (SELECT COUNT(*) FROM projects WHERE deleted_at IS NOT NULL) + '
                  '(SELECT COUNT(*) FROM tasks WHERE deleted_at IS NOT NULL) AS n',
                )
                .single['n']
            as int);
    final sourceOwner = _ownerOf(source.raw);

    var localOnly = 0;
    var unclassified = 0;
    var orphaned = 0;
    final importableProjects = <Project>[];
    for (final p in projects) {
      switch (projectScope[p.id]) {
        case 'synced':
          importableProjects.add(p);
        case 'local_only':
          localOnly++;
        default:
          unclassified++;
      }
    }
    final importableIds = {for (final p in importableProjects) p.id};
    final targetProjects = await repository.loadProjects();
    final byProject = <String, List<Task>>{};
    for (final t in tasks) {
      final scope = taskScope[t.id];
      if (!importableIds.contains(t.projectId)) {
        // Counted with the project's class below.
        if (projectScope[t.projectId] == 'local_only') {
          localOnly++;
        } else if (projectScope[t.projectId] != null) {
          unclassified++;
        }
        continue;
      }
      if (scope == 'local_only') {
        localOnly++;
      } else if (scope != 'synced') {
        unclassified++;
      } else {
        byProject.putIfAbsent(t.projectId, () => []).add(t);
      }
    }
    final candidates = <ImportCandidate>[];
    for (final p in importableProjects) {
      final list = byProject[p.id] ?? const <Task>[];
      final ordered = _parentsFirst(list);
      orphaned += list.length - ordered.length;
      final mapped = _metaValue(_mapKey(sourceOwner, 'p', p.id));
      final liveMapped =
          mapped != null && targetProjects.any((tp) => tp.id == mapped);
      final sameName = targetProjects
          .where(
            (tp) => tp.name.trim().toLowerCase() == p.name.trim().toLowerCase(),
          )
          .map((tp) => tp.id)
          .firstOrNull;
      candidates.add(
        ImportCandidate(
          project: p,
          tasks: ordered,
          alreadyImportedAs: liveMapped ? mapped : null,
          sameNameProjectId: sameName,
          warnings: {
            if (liveMapped) ImportWarning.alreadyImported,
            if (sameName != null) ImportWarning.sameNameExists,
          },
        ),
      );
    }
    return ImportPreview(
      sourceOwnerId: sourceOwner,
      candidates: candidates,
      skipped: ImportSkipped(
        localOnly: localOnly,
        unclassified: unclassified,
        deleted: deleted,
        orphaned: orphaned,
      ),
    );
  }

  /// Runs the choices: backup, then one transaction.
  Future<ImportResult> run(List<ImportChoice> choices) async {
    if (choices.isEmpty) {
      throw const ImportException('nothing_selected');
    }
    final source = _openSource();
    final ImportPreview preview;
    try {
      preview = await _preview(source);
    } finally {
      source.close();
    }
    final byId = {for (final c in preview.candidates) c.project.id: c};
    final targetProjects = await repository.loadProjects();
    final targetTasks = await repository.loadTasks();

    final newProjects = <Project>[];
    final newTasks = <Task>[];
    final meta = <String, String>{};
    var skippedDuplicates = 0;
    var projectsCreated = 0;
    var nextProjectPosition = targetProjects.isEmpty
        ? 0
        : targetProjects
                  .map((p) => p.position)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final usedSources = <String>{};
    for (final choice in choices) {
      final candidate = byId[choice.sourceProjectId];
      if (candidate == null) {
        throw ImportException('unknown_source', choice.sourceProjectId);
      }
      if (!usedSources.add(choice.sourceProjectId)) {
        throw ImportException('unknown_source', 'listed twice');
      }
      if (candidate.warnings.contains(ImportWarning.alreadyImported) &&
          !choice.allowDuplicate) {
        throw ImportException('blocked_duplicate', candidate.project.name);
      }
      final destination = choice.destinationProjectId;
      late final String destinationId;
      var destinationTasks = <Task>[];
      if (destination == null) {
        destinationId = _ids.nextId();
        newProjects.add(
          Project(
            id: destinationId,
            name: candidate.project.name,
            position: nextProjectPosition++,
          ),
        );
        meta[_mapKey(preview.sourceOwnerId, 'p', candidate.project.id)] =
            destinationId;
        projectsCreated++;
      } else {
        if (!targetProjects.any((p) => p.id == destination)) {
          throw ImportException('unknown_destination', destination);
        }
        destinationId = destination;
        destinationTasks = [
          for (final t in targetTasks)
            if (t.projectId == destination) t,
        ];
      }
      final idMap = <String, String>{};
      final existingKeys = {
        for (final t in destinationTasks) _taskKey(t, destinationTasks),
      };
      final offset =
          destinationTasks
              .where((t) => t.parentId == null)
              .fold<int>(-1, (m, t) => t.position > m ? t.position : m) +
          1;
      for (final t in candidate.tasks) {
        if (destination != null) {
          // Duplicate detection inside an existing destination: same title under
          // the same parent path.
          final key = _importKey(t, candidate.tasks, idMap, destinationTasks);
          if (key != null && existingKeys.contains(key)) {
            skippedDuplicates++;
            // Children of a skipped duplicate map onto the existing task.
            final existing = _existingFor(key, destinationTasks);
            if (existing != null) {
              idMap[t.id] = existing.id;
            }
            continue;
          }
        }
        final newId = _ids.nextId();
        idMap[t.id] = newId;
        final parent = t.parentId == null ? null : idMap[t.parentId];
        if (t.parentId != null && parent == null) {
          skippedDuplicates++; // its parent was not importable
          idMap.remove(t.id);
          continue;
        }
        newTasks.add(
          Task(
            id: newId,
            projectId: destinationId,
            parentId: parent,
            title: t.title,
            notes: t.notes,
            status: t.status,
            priority: t.priority,
            dueDate: t.dueDate,
            position: t.parentId == null && destination != null
                ? t.position + offset
                : t.position,
          ),
        );
        meta[_mapKey(preview.sourceOwnerId, 't', t.id)] = newId;
      }
    }

    final backup = await _backupTarget();
    try {
      await repository.importBatch(
        projects: newProjects,
        tasks: newTasks,
        meta: meta,
        beforeCommit: beforeCommit,
      );
    } on RepositoryException catch (error) {
      throw ImportException('write_failed', error.message);
    } on Object catch (error) {
      throw ImportException('write_failed', '$error');
    }
    return ImportResult(
      projectsCreated: projectsCreated,
      tasksImported: newTasks.length,
      tasksSkippedDuplicate: skippedDuplicates,
      backupFile: backup,
    );
  }

  // ------------------------------------------------------------- helpers

  /// Parents before children; a task whose parent is not in [tasks] is dropped
  /// (counted as orphaned by the caller), never re-parented.
  List<Task> _parentsFirst(List<Task> tasks) {
    final byId = {for (final t in tasks) t.id: t};
    final out = <Task>[];
    final done = <String>{};
    var progress = true;
    var pending = List<Task>.of(tasks);
    while (progress && pending.isNotEmpty) {
      progress = false;
      final next = <Task>[];
      for (final t in pending) {
        final p = t.parentId;
        if (p == null || done.contains(p)) {
          out.add(t);
          done.add(t.id);
          progress = true;
        } else if (byId.containsKey(p)) {
          next.add(t);
        }
      }
      pending = next;
    }
    return out;
  }

  String _taskKey(Task t, List<Task> within) {
    final parts = <String>[];
    Task? cursor = t;
    final byId = {for (final x in within) x.id: x};
    while (cursor != null) {
      parts.add(cursor.title.trim().toLowerCase());
      cursor = cursor.parentId == null ? null : byId[cursor.parentId];
    }
    return parts.reversed.join('\u0001');
  }

  /// The duplicate key of a source task, computed over the destination's tree
  /// through the ids already mapped; null when its parent is not mapped.
  String? _importKey(
    Task t,
    List<Task> sourceTasks,
    Map<String, String> idMap,
    List<Task> destination,
  ) {
    if (t.parentId == null) {
      return t.title.trim().toLowerCase();
    }
    final parentNew = idMap[t.parentId];
    if (parentNew == null) {
      return null;
    }
    final parent = destination.where((d) => d.id == parentNew).firstOrNull;
    if (parent == null) {
      return null; // the parent was freshly imported: nothing to compare with
    }
    return '${_taskKey(parent, destination)}\u0001${t.title.trim().toLowerCase()}';
  }

  Task? _existingFor(String key, List<Task> destination) {
    for (final t in destination) {
      if (_taskKey(t, destination) == key) {
        return t;
      }
    }
    return null;
  }

  String _ownerOf(Database db) {
    final rows = db.select("SELECT value FROM meta WHERE key = 'user_id'");
    return rows.isEmpty ? 'local' : rows.single['value'] as String;
  }

  String? _metaValue(String key) {
    final rows = target.raw.select('SELECT value FROM meta WHERE key = ?', [
      key,
    ]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  /// A copy of the account database made with `VACUUM INTO` and proven equal to
  /// the original by a content digest. A copy that does not verify is renamed
  /// `.failed`, kept, and the import stops before writing anything.
  Future<String> _backupTarget() async {
    final file = File(target.filePath);
    final dir = backupDirectory ?? file.parent.path;
    Directory(dir).createSync(recursive: true);
    final stamp = _now()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .padRight(17, '0')
        .substring(0, 17);
    var path =
        '$dir${Platform.pathSeparator}${_name(file.path)}.pre-import-$stamp.bak';
    var n = 1;
    while (File(path).existsSync()) {
      path =
          '$dir${Platform.pathSeparator}${_name(file.path)}.pre-import-$stamp-$n.bak';
      n++;
    }
    try {
      target.raw.execute('VACUUM INTO ?', [path]);
      final copy = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        if (snapshotDigest(copy) != snapshotDigest(target.raw)) {
          throw const ImportException('backup_failed', 'digest mismatch');
        }
      } finally {
        copy.close();
      }
    } on ImportException {
      _keepFailed(path);
      rethrow;
    } on SqliteException catch (error) {
      _keepFailed(path);
      throw ImportException('backup_failed', error.message);
    }
    return path;
  }

  void _keepFailed(String path) {
    final f = File(path);
    if (f.existsSync()) {
      f.renameSync('$path.failed');
    }
  }

  String _name(String path) => path.split(RegExp(r'[\\/]')).last;
}
