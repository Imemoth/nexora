import 'dart:async';
import 'dart:convert';

import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/data/entity_patch.dart'
    show normalizeDueTime;
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';

/// How one side of a conflicting field is shown.
enum ConflictSideState {
  /// A value is recorded (possibly empty: see [ConflictSide.text]).
  value,

  /// The entity is deleted on this side.
  deleted,

  /// The stored evidence does not contain this value. Nothing is invented.
  unavailable,
}

final class ConflictSide {
  const ConflictSide.value(String this.text) : state = ConflictSideState.value;
  const ConflictSide.deleted() : state = ConflictSideState.deleted, text = null;
  const ConflictSide.unavailable()
    : state = ConflictSideState.unavailable,
      text = null;

  final ConflictSideState state;
  final String? text;

  @override
  bool operator ==(Object other) =>
      other is ConflictSide && other.state == state && other.text == text;

  @override
  int get hashCode => Object.hash(state, text);
}

/// One row of the side-by-side comparison. The raw stored values stay behind
/// this model: the UI never sees JSON.
final class ConflictFieldView {
  const ConflictFieldView({
    required this.field,
    required this.label,
    required this.local,
    required this.server,
    required this.differs,
    this.canPick = false,
  });

  /// The server field name (`title`, `notes`, ...). Used only for picking.
  final String field;
  final String label;
  final ConflictSide local;
  final ConflictSide server;

  /// The two sides differ (highlighted in the UI).
  final bool differs;

  /// The user may pick a side for this field when merging.
  final bool canPick;
}

/// Where a conflict stands from the user's point of view.
enum ConflictStatus {
  /// Waiting for the user's decision.
  open,

  /// Another device already decided on the server; this device still has to
  /// apply the outcome to its own pending change.
  decidedElsewhere,
}

/// Which side the user keeps for a field when merging.
enum MergePick { local, server }

/// Everything the UI needs about one unresolved conflict.
final class ConflictView {
  const ConflictView({
    required this.id,
    required this.entityType,
    required this.entityName,
    required this.projectName,
    required this.kind,
    required this.fields,
    required this.choices,
    required this.status,
  });

  final String id;
  final String entityType;
  final String entityName;
  final String? projectName;

  /// The server's conflict kind (`field`, `edit_deleted`, ...). Drives wording.
  final String kind;
  final List<ConflictFieldView> fields;

  /// Only the strategies that are valid for this conflict.
  final Set<ConflictChoice> choices;
  final ConflictStatus status;

  bool get isTask => entityType == 'task';

  /// The fields a merge lets the user pick a side for.
  List<ConflictFieldView> get mergeFields =>
      fields.where((f) => f.canPick).toList();
}

/// What came of a resolution attempt, in terms the UI can explain.
enum ConflictOutcomeKind {
  /// The server confirmed the decision and the device applied it.
  resolved,

  /// The service could not be reached. Nothing changed; retry later.
  offline,

  /// A new sign-in is needed. Nothing changed.
  authRequired,

  /// This device was revoked. Nothing changed.
  deviceRevoked,

  /// The conflict was already decided on another device; this device will
  /// catch up on the next synchronization.
  alreadyDecidedElsewhere,

  /// The server refused the decision. Nothing changed.
  rejected,

  /// The choice is not valid for this conflict (nothing was sent).
  unsupported,

  /// A decision for this conflict is already being sent.
  inProgress,

  /// The conflict is no longer in the list (handled meanwhile).
  notFound,

  /// An unexpected problem. Nothing changed.
  failed,
}

final class ConflictOutcome {
  const ConflictOutcome(this.kind, [this.code]);

  final ConflictOutcomeKind kind;

  /// A stable technical code for support, never user data.
  final String? code;

  bool get ok => kind == ConflictOutcomeKind.resolved;
}

/// Lists the unresolved conflicts and applies the user's decisions, through the
/// engine. Widgets use this (via the runtime); they never touch the tables.
///
/// Rules:
/// * a decision is sent to the server first; the local conflict is completed
///   only after the server confirmed it (never a success before that);
/// * a failure changes nothing: the pending local operation and the conflict
///   evidence stay exactly as they were;
/// * a retry reuses the stored operation id, so a lost response never resolves
///   twice (the engine's rule);
/// * only one decision per conflict runs at a time.
final class ConflictService {
  ConflictService({
    required this.outbox,
    required this.db,
    required this._engine,
  });

  final OutboxStore outbox;
  final LocalDatabase db;
  final SyncEngine? Function() _engine;
  final Set<String> _running = {};

  /// The unresolved conflicts, oldest first.
  List<ConflictView> list() {
    final views = <ConflictView>[];
    for (final row in outbox.conflictsNeedingAction()) {
      try {
        views.add(_build(row));
      } on Object {
        // A conflict whose evidence cannot be read is still listed, with the
        // only decision that needs no evidence.
        views.add(_fallback(row));
      }
    }
    return views;
  }

  /// Applies [choice] to the conflict [id].
  ///
  /// [picks] is required for [ConflictChoice.merge]: one pick for every field
  /// the merge covers.
  Future<ConflictOutcome> resolve(
    String id,
    ConflictChoice choice, {
    Map<String, MergePick>? picks,
  }) async {
    final view = list().where((c) => c.id == id).firstOrNull;
    if (view == null) {
      return const ConflictOutcome(ConflictOutcomeKind.notFound);
    }
    if (!view.choices.contains(choice)) {
      return const ConflictOutcome(ConflictOutcomeKind.unsupported, 'choice');
    }
    Map<String, Object?>? values;
    if (choice == ConflictChoice.merge) {
      values = _mergeValues(id, view, picks);
      if (values == null) {
        return const ConflictOutcome(ConflictOutcomeKind.unsupported, 'picks');
      }
    }
    if (!_running.add(id)) {
      return const ConflictOutcome(ConflictOutcomeKind.inProgress);
    }
    try {
      if (view.status == ConflictStatus.decidedElsewhere) {
        return _completeLocally(id, choice);
      }
      final engine = _engine();
      if (engine == null) {
        return const ConflictOutcome(ConflictOutcomeKind.authRequired);
      }
      try {
        await engine.resolveConflict(id, choice, values: values);
        return const ConflictOutcome(ConflictOutcomeKind.resolved);
      } on SyncNetworkFailure catch (error) {
        return ConflictOutcome(ConflictOutcomeKind.offline, error.message);
      } on SyncAuthFailure {
        return const ConflictOutcome(ConflictOutcomeKind.authRequired);
      } on SyncServerError catch (error) {
        if (error.code == 'device_invalid') {
          return const ConflictOutcome(ConflictOutcomeKind.deviceRevoked);
        }
        return ConflictOutcome(ConflictOutcomeKind.rejected, error.code);
      } on ResolveRejected catch (error) {
        if (error.code == 'conflict_not_open') {
          return const ConflictOutcome(
            ConflictOutcomeKind.alreadyDecidedElsewhere,
            'conflict_not_open',
          );
        }
        return ConflictOutcome(ConflictOutcomeKind.rejected, error.code);
      } on RepositoryException catch (error) {
        // The conflict was handled meanwhile (for example by a second click).
        return ConflictOutcome(ConflictOutcomeKind.notFound, error.message);
      }
    } on Object catch (error) {
      return ConflictOutcome(
        ConflictOutcomeKind.failed,
        '${error.runtimeType}',
      );
    } finally {
      _running.remove(id);
    }
  }

  /// True while a decision for [id] is being sent.
  bool isResolving(String id) => _running.contains(id);

  // ------------------------------------------------------------- internals

  /// The conflict was decided on the server by another device: no server call
  /// is needed, only the local pending change has to be settled.
  ConflictOutcome _completeLocally(String id, ConflictChoice choice) {
    switch (choice) {
      case ConflictChoice.useServer:
        outbox.resolveConflictUseServer(id);
      case ConflictChoice.keepLocal:
        outbox.resolveConflictRetryLocal(id);
      case ConflictChoice.merge:
      case ConflictChoice.recreateCopy:
        return const ConflictOutcome(ConflictOutcomeKind.unsupported, 'choice');
    }
    return const ConflictOutcome(ConflictOutcomeKind.resolved);
  }

  Map<String, Object?>? _mergeValues(
    String id,
    ConflictView view,
    Map<String, MergePick>? picks,
  ) {
    if (picks == null) {
      return null;
    }
    final row = outbox
        .conflictsNeedingAction()
        .where((c) => c['id'] == id)
        .firstOrNull;
    if (row == null) {
      return null;
    }
    final client = _map(row['client_value_json']);
    final server = _map(row['server_value_json']);
    final values = <String, Object?>{};
    for (final field in view.mergeFields) {
      final pick = picks[field.field];
      if (pick == null) {
        return null;
      }
      final source = pick == MergePick.local ? client : server;
      if (!source.containsKey(field.field)) {
        return null;
      }
      // A time from the server row is `17:30:00`; the wire form is `17:30`.
      values[field.field] = field.field == 'due_time'
          ? normalizeDueTime(source[field.field])
          : source[field.field];
    }
    return values.isEmpty ? null : values;
  }

  static Map<String, Object?> _map(Object? json) {
    if (json is! String) {
      return {};
    }
    final decoded = jsonDecode(json);
    return decoded is Map ? Map<String, Object?>.from(decoded) : {};
  }

  ConflictView _fallback(Map<String, Object?> row) {
    final type = row['entity_type'] as String;
    return ConflictView(
      id: row['id'] as String,
      entityType: type,
      entityName: _unavailableName,
      projectName: null,
      kind: (row['kind'] as String?) ?? 'field',
      fields: const [],
      choices: const {ConflictChoice.useServer},
      status: row['status'] == 'open'
          ? ConflictStatus.open
          : ConflictStatus.decidedElsewhere,
    );
  }

  static const String _unavailableName = '(name not available)';

  ConflictView _build(Map<String, Object?> row) {
    final type = row['entity_type'] as String;
    final entityId = row['entity_id'] as String;
    final kind = row['kind'] as String;
    final fieldNames = (jsonDecode(row['fields_json'] as String) as List)
        .whereType<String>()
        .toList();
    final client = _map(row['client_value_json']);
    final server = _map(row['server_value_json']);
    final snapshot = outbox.serverSnapshot(type, entityId);
    final local = _localRow(type, entityId);
    final isTree = client.containsKey('tree');

    final name = type == 'task'
        ? (local?['title'] ?? snapshot?['title'])
        : (local?['name'] ?? snapshot?['name']);
    final projectId = type == 'task'
        ? (local?['project_id'] ?? snapshot?['project_id'])
        : entityId;
    final projectName = type == 'task' && projectId is String
        ? _projectName(projectId, snapshot)
        : null;

    final fields = <ConflictFieldView>[];
    switch (kind) {
      case 'field':
      case 'exists':
        for (final f in fieldNames) {
          fields.add(
            _field(
              type,
              f,
              local: client.containsKey(f)
                  ? ConflictSide.value(_format(type, f, client[f], snapshot))
                  : const ConflictSide.unavailable(),
              server: server.containsKey(f)
                  ? ConflictSide.value(_format(type, f, server[f], snapshot))
                  : const ConflictSide.unavailable(),
              canPick: client.containsKey(f) && server.containsKey(f),
            ),
          );
        }
      case 'edit_deleted':
        fields.add(
          ConflictFieldView(
            field: '_item',
            label: _itemLabel(type),
            local: const ConflictSide.value('Changed by you'),
            server: const ConflictSide.deleted(),
            differs: true,
          ),
        );
        for (final f in fieldNames) {
          if (client.containsKey(f)) {
            fields.add(
              _field(
                type,
                f,
                local: ConflictSide.value(
                  _format(type, f, client[f], snapshot),
                ),
                server: const ConflictSide.deleted(),
              ),
            );
          }
        }
      case 'delete_edited':
      case 'parent_has_live_children':
        fields.add(
          ConflictFieldView(
            field: '_item',
            label: _itemLabel(type),
            local: const ConflictSide.deleted(),
            server: ConflictSide.value(
              kind == 'delete_edited'
                  ? 'Changed on the server'
                  : 'Still has other items',
            ),
            differs: true,
          ),
        );
        if (kind == 'delete_edited' && local != null && snapshot != null) {
          final names = type == 'task'
              ? const [
                  'title',
                  'notes',
                  'status',
                  'priority',
                  'due_date',
                  'due_time',
                ]
              : const ['name'];
          for (final f in names) {
            if (!local.containsKey(f) || !snapshot.containsKey(f)) {
              continue;
            }
            fields.add(
              _field(
                type,
                f,
                local: ConflictSide.value(_format(type, f, local[f], snapshot)),
                server: ConflictSide.value(
                  _format(type, f, snapshot[f], snapshot),
                ),
              ),
            );
          }
        }
      default:
        fields.add(
          ConflictFieldView(
            field: '_item',
            label: _itemLabel(type),
            local: const ConflictSide.unavailable(),
            server: const ConflictSide.unavailable(),
            differs: false,
          ),
        );
    }

    final elsewhere = row['status'] != 'open';
    final choices = <ConflictChoice>{ConflictChoice.useServer};
    if (elsewhere) {
      choices.add(ConflictChoice.keepLocal);
    } else {
      switch (kind) {
        case 'field':
        case 'exists':
          choices.add(ConflictChoice.keepLocal);
          if (fields.where((f) => f.canPick).length > 1) {
            choices.add(ConflictChoice.merge);
          }
        case 'edit_deleted':
          choices.add(ConflictChoice.recreateCopy);
        case 'delete_edited':
          choices.add(ConflictChoice.keepLocal);
        case 'parent_has_live_children':
          if (isTree) {
            choices.add(ConflictChoice.keepLocal);
          }
      }
    }
    return ConflictView(
      id: row['id'] as String,
      entityType: type,
      entityName: name is String && name.isNotEmpty ? name : _unavailableName,
      projectName: projectName,
      kind: kind,
      fields: fields,
      choices: choices,
      status: elsewhere ? ConflictStatus.decidedElsewhere : ConflictStatus.open,
    );
  }

  ConflictFieldView _field(
    String type,
    String field, {
    required ConflictSide local,
    required ConflictSide server,
    bool canPick = false,
  }) {
    return ConflictFieldView(
      field: field,
      label: _label(type, field),
      local: local,
      server: server,
      differs: local != server,
      canPick: canPick,
    );
  }

  Map<String, Object?>? _localRow(String type, String id) {
    final table = type == 'task' ? 'tasks' : 'projects';
    final rows = db.raw.select('SELECT * FROM $table WHERE id = ?', [id]);
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(rows.single);
  }

  String? _projectName(String projectId, Map<String, Object?>? snapshot) {
    final rows = db.raw.select('SELECT name FROM projects WHERE id = ?', [
      projectId,
    ]);
    if (rows.isNotEmpty) {
      return rows.single['name'] as String?;
    }
    final snap = outbox.serverSnapshot('project', projectId);
    return snap?['name'] as String?;
  }

  String _itemLabel(String type) => type == 'task' ? 'Task' : 'Project';

  static String _label(String type, String field) {
    switch (field) {
      case 'title':
        return 'Title';
      case 'name':
        return 'Name';
      case 'notes':
        return 'Notes';
      case 'status':
        return 'Status';
      case 'priority':
        return 'Priority';
      case 'due_date':
        return 'Due date';
      case 'due_time':
        return 'Due time';
      case 'completed_at':
        return 'Completed';
      case 'parent_id':
        return 'Parent task';
      case 'sort_order':
        return 'Order';
      case 'description':
        return 'Description';
      case 'color':
        return 'Colour';
      case 'is_archived':
        return 'Archived';
    }
    return field;
  }

  String _format(
    String type,
    String field,
    Object? value,
    Map<String, Object?>? snapshot,
  ) {
    if (value == null) {
      return switch (field) {
        'due_date' => 'No due date',
        'due_time' => 'No time (date only)',
        'parent_id' => 'No parent (top level)',
        'completed_at' => 'Not completed',
        'notes' || 'description' => '(empty)',
        _ => '(none)',
      };
    }
    switch (field) {
      case 'status':
        return switch (value) {
          'open' => 'Open',
          'in_progress' => 'In progress',
          'review' => 'In review',
          'done' => 'Done',
          'archived' => 'Archived',
          _ => '$value',
        };
      case 'priority':
        return switch (value) {
          'none' => 'No priority',
          'low' => 'Low',
          'medium' => 'Medium',
          'high' => 'High',
          _ => '$value',
        };
      case 'due_time':
        // The server answers 17:30:00; people read 17:30.
        return normalizeDueTime(value) ?? '$value';
      case 'parent_id':
        if (value is String) {
          final rows = db.raw.select('SELECT title FROM tasks WHERE id = ?', [
            value,
          ]);
          if (rows.isNotEmpty) {
            return rows.single['title'] as String;
          }
          final snap = outbox.serverSnapshot('task', value);
          final title = snap?['title'];
          return title is String ? title : '(task not available)';
        }
      case 'notes':
      case 'description':
        if (value is String && value.isEmpty) {
          return '(empty)';
        }
    }
    return '$value';
  }
}
