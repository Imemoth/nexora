# Nexora Phase 1 — Desktop UI Implementation Plan (v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Do not start implementation until this plan is merged and the owner accepts the Task 1 proposal.**

**Goal:** Build a modern, dark, three-pane Windows desktop UI over deterministic in-memory demo data. Implement smart views, projects, a recursive task tree, a details editor, minimal task and subtask creation, search, sorting, keyboard navigation and accessibility fundamentals, with clean boundaries for the Phase 2 SQLite repository.

**Architecture:** Pure Dart domain and application layers. The application layer (`TaskWorkspace`) holds all state, the edit draft and the unsaved-change gate, and talks to an async `TaskRepository` interface. A thin Flutter `ChangeNotifier` adapter in presentation forwards workspace state to widgets. Widgets render state and send intents; they hold no business state.

**Tech Stack:** Flutter 3.47.9 (stable) / Dart 3.13.7, pinned in CI as in Phase 0. flutter_test, flutter_lints. No new runtime dependencies (Section 4).

**Predecessors:**
- Spec: [docs/superpowers/specs/2026-11-11-nexora-v1-design.md](../specs/2026-11-11-nexora-v1-design.md)
- Phase 0 plan (merged in PR #2, merge commit `a05b353`): [2026-11-11-nexora-phase-0-foundation.md](2026-11-11-nexora-phase-0-foundation.md)
- ADR: [docs/architecture/decisions/0001-flutter-offline-first.md](../../architecture/decisions/0001-flutter-offline-first.md)
- Sync contract: [docs/architecture/sync-contract.md](../../architecture/sync-contract.md)

---

## Change log (v2, owner review of v1 at `a0de8a8`)

Owner approved decisions 1–12 in principle (recommended options; see Section 9) and required three corrections. This version applies them:

1. **Create-task and create-subtask** are specified end to end: domain rules, application operations, repository use, UI interactions, validation, deterministic ordering, and tests (Sections 2, 3, 5, 8).
2. **Application-layer dependency contradiction resolved.** The application layer is pure Dart. `TaskWorkspace` replaces the Flutter `ChangeNotifier` controller. A thin `TasksNotifier` (`ChangeNotifier`) lives in presentation and only forwards state. Architecture tests are updated accordingly (Section 3.4, Task 1 and Task 2).
3. **Unsaved-change handling covers every navigation and visibility transition.** Failed saves keep the draft and block the transition. The draft now lives in the application layer, so one gate covers all paths (Section 5.4).
4. **UI strings are centralized** in `AppStrings` for later localization (Section 5.6).

---

## 0. Reconciliation with existing decisions

| Item | Status on `main` (`a05b353`) | Phase 1 decision |
|---|---|---|
| `TaskStatus { open, inProgress, review, done, archived }` | Exists (`lib/features/tasks/domain/task_status.dart`) | Reused unchanged |
| `summarizeChildren` / `TaskCompletion` (direct children; `eligibleForReview` never sets `done`) | Exists (`task_completion.dart`) | Reused unchanged. Recursion is a separate projection |
| Parent completion: manual closure, derived review hint only | Phase 0 test `task_completion_test.dart` | Preserved (owner decision 10 = derived only) |
| Supabase access: verified read-only, no hosted writes | `docs/operations/supabase-access.md` | Phase 1 has no Supabase code and no network |
| Phase 1 plan | Named in Phase 0 plan's "Subsequent Plans" | This file |
| `Task`, `Project`, `TaskPriority`, `CalendarDate`, `Clock`, `IdGenerator`, `TaskRepository`, `TaskWorkspace` | Do not exist | Created in Phase 1 |
| Spec: date-only vs timestamp deadlines | Open | Date-only `CalendarDate` (decision 1) |

No duplicate work is planned. Phase 1 adds to the Phase 0 domain and does not change it.

---

## 1. Scope

### In scope
- Three-pane shell: left navigation, center task list, right details editor.
- Left navigation: Today, Next 7 Days, Overdue, All, and a Projects section, with live counts.
- Center pane: recursive task tree with deterministic ordering, expand/collapse, `done/total` for parents, and the derived "Ready for review" hint.
- Right pane: edit title, status, priority, due date (date-only) and plain-text notes. Explicit Save and Revert.
- **Create task** (root task in a project) and **create subtask** (child of a non-archived task). No deletion.
- Unsaved-change gate for every selection, visibility and exit transition (Section 5.4).
- Search (title and notes, case-insensitive), sorting (position, due date, priority, title), empty states, clear-selection behavior.
- Dark theme by default. English UI strings, ISO dates, centralized in `AppStrings`.
- Keyboard navigation and accessibility fundamentals.
- Deterministic demo data.

### Out of scope (Phase 1)
- SQLite, persistence across restarts, autosave (Phase 2).
- Supabase, auth, sync, conflicts, RLS (Phase 3).
- Reminders, tray, notifications, export/import, release acceptance beyond the Phase 0 ZIP gate (Phase 4).
- Light theme, task deletion, rich-text or markdown notes, moving tasks between parents, multi-workspace and sharing.

---

## 2. Domain model (pure Dart)

Files under `lib/features/tasks/domain/` and `lib/core/`. Imports only `dart:` libraries and this package's own files. No `package:flutter`.

| Type | Kind | Notes |
|---|---|---|
| `TaskStatus` | enum (exists) | `open, inProgress, review, done, archived` |
| `TaskPriority` | enum (new) | `none, low, medium, high` |
| `CalendarDate` | value class (new) | `year, month, day`; ordering; `addDays`; no time zone; `toIsoString()` → `YYYY-MM-DD` |
| `Clock` | abstract interface (new) | `CalendarDate today()`. `SystemClock` in `main.dart` wiring; tests use a fixed clock |
| `IdGenerator` | abstract interface (new, `lib/core/ids/`) | `String nextId()`. Production: `RandomIdGenerator` (UUID v4 from `Random.secure()`, no package). Tests: sequential fake |
| `Result<T, E>` | sealed class (new, `lib/core/result.dart`) | `Ok(value)` / `Err(error)`; no exceptions for validation |
| `Task` | immutable class (new) | `id, projectId, parentId?, title, status, priority, dueDate?, notes, position`; `copyWith` |
| `Project` | immutable class (new) | `id, name, position` |
| `TaskTreeRules` | pure functions (new) | `validateParentChange` |
| `TaskCreationRules` | pure functions (new) | `createRootTask`, `createSubtask`; see 2.2 |
| `TaskValidation` | pure functions (new) | `validateTitle`, `validateDraftFields` |
| `completionOf` | function (new) | Applies `summarizeChildren` to direct children from a task map |
| `SmartView` | enum (new) | `today, next7Days, overdue, all` |
| `SmartViewRules` | pure functions (new) | `matches(task, view, today)` |
| `TaskOrdering` | pure functions (new) | Sibling and flat-list order; sort options |
| `TaskSearch` | pure function (new) | Case-insensitive substring over title and notes |

### 2.1 Parent change validation
`TaskTreeRules.validateParentChange(tasks, taskId, newParentId)` returns `Ok` or `Err` with one of `selfParent`, `cycle`, `crossProject`, `missingParent`. Phase 1 UI never changes `parentId`, but the rule is checked on every save so it stays enforced when moves are added later.

### 2.2 Create task and create subtask (new in v2)

**Root task** — `TaskCreationRules.createRootTask({required String title, required String projectId, required Map<String, Project> projects, required Iterable<Task> tasks, required IdGenerator ids})`:
1. `title` passes `TaskValidation.validateTitle` (below). Error → `Err(CreateError.title*)`.
2. `projectId` must exist in `projects`. Missing → `Err(CreateError.unknownProject)`.
3. Position = max `position` among tasks with `projectId` and `parentId == null`, plus 1; first task gets 0.
4. New task: `status = open`, `priority = none`, `dueDate = null`, `notes = ''`, `parentId = null`.
5. `id = ids.nextId()`. If the id already exists in `tasks` → `Err(CreateError.idCollision)` (defensive; never expected with UUID v4).
6. Returns `Ok(Task)`. The function never mutates input.

**Subtask** — `TaskCreationRules.createSubtask({required String title, required String parentId, required Iterable<Task> tasks, required IdGenerator ids})`:
1. `title` as above.
2. Parent must exist → else `Err(CreateError.unknownParent)`.
3. Parent status must not be `archived` → else `Err(CreateError.parentArchived)`.
4. New task inherits `projectId` from the parent (the only way to get a cross-project child is rejected by construction).
5. Position = max `position` among children of `parentId` plus 1; first child gets 0.
6. Other fields and the id rule as for root tasks.
7. Parent status is **not** changed. A parent that was `done` keeps `done`, and its completion hint updates from the new child (derived only, decision 10).

**Title validation** — `TaskValidation.validateTitle(String raw)`: trim whitespace; empty → `Err(TitleError.required)`; longer than 200 UTF-16 code units → `Err(TitleError.tooLong)`; otherwise `Ok(trimmed)`. The trimmed value is what gets stored.

**Deterministic ordering** — siblings sort by `position`, then `id`. Creation appends (max + 1), so the order of created items is the order of creation and never depends on hash iteration. Sort options (Section 2.3) apply only to display order in the list, not to stored positions.

### 2.3 Ordering and sort options
- `position` (default): siblings by `position`, then `id`.
- `dueDate`: tasks with a due date first in ascending date order; tasks without a due date last; ties by `position`, then `id`.
- `priority`: `high, medium, low, none`; ties by `position`, then `id`.
- `title`: case-insensitive comparison of the trimmed title; ties by `id`.
- The flat list is a depth-first walk over the chosen sort applied to each sibling group.

### 2.4 Smart views (`today` from the injected `Clock`)
- `today`: `dueDate == today`, status not `done` or `archived`.
- `next7Days`: `today < dueDate <= today + 7`, status not `done` or `archived` (decision 2: tomorrow through today+7).
- `overdue`: `dueDate < today`, status not `done` or `archived`.
- `all`: every task, including archived (decision 12), shown with an "archived" chip.

### 2.5 Recursive completion
`completionOf(taskId, tasks)` uses direct children only, as in Phase 0. A parent's status is never written from this projection.

### 2.6 Domain tests (written first, Task 1)
- `CalendarDate`: ordering, `addDays` across month and year boundaries, leap day, ISO format.
- `TaskTreeRules`: self-parent, cycle (A→B→C, A under C), cross-project, missing parent rejected; valid move accepted.
- `TaskCreationRules`: root task gets max+1 position, default fields, trimmed title; empty title, whitespace-only title, 201-character title rejected; unknown project rejected; subtask under archived parent rejected; subtask under unknown parent rejected; subtask inherits project; creating three subtasks yields positions 0,1,2 in creation order; creation never changes an existing task (input immutability test); id collision rejected.
- `completionOf`: `[done, done]` → eligible, parent status unchanged; grandchild does not change parent direct counts; no children → not eligible.
- `SmartViewRules`: boundary table with a fixed `today` (today, today+1, today+7, today+8, yesterday, done, archived) for each view.
- `TaskOrdering`: stable across repeated calls; id tie-break; due-date sort puts undated tasks last; title sort is case-insensitive.
- `TaskSearch`: case-insensitive; matches notes; empty query matches all.

---

## 3. Application layer (pure Dart)

Files under `lib/features/tasks/application/`. Imports only `dart:` libraries, `lib/core/`, and this package's domain files. No `package:flutter`.

### 3.1 Repository

```dart
abstract interface class TaskRepository {
  Future<List<Project>> loadProjects();
  Future<List<Task>> loadTasks();
  /// Insert or replace. Throws RepositoryException on failure.
  Future<void> saveTask(Task task);
}

final class RepositoryException implements Exception {
  const RepositoryException(this.message);
  final String message; // diagnostic only; never shown to users verbatim
}
```

`InMemoryTaskRepository` (Phase 1 only) implements this with an in-memory map and an optional `failNextSave` switch used by tests to simulate a failed save.

### 3.2 Workspace state

```dart
final class WorkspaceState {
  final List<Project> projects;
  final Map<String, Task> tasks;             // by id
  final NavSelection selection;              // SmartViewSelection | ProjectSelection
  final String searchQuery;
  final TaskSort sort;
  final String? selectedTaskId;
  final Set<String> expandedTaskIds;
  final EditDraft? draft;                    // null when no draft exists
  final PendingTransition? pending;          // non-null while the gate is open
  final WorkspaceError? error;               // last user-visible error code
  final bool loading;
}

final class EditDraft {
  final String taskId;
  final Task base;                           // persisted snapshot
  final String title;
  final TaskStatus status;
  final TaskPriority priority;
  final CalendarDate? dueDate;
  final String notes;
  bool get isDirty; // any field differs from base
}

enum WorkspaceError { titleRequired, titleTooLong, unknownProject, unknownParent, parentArchived,
  saveFailed, loadFailed }
```

`WorkspaceError` is a code. Presentation maps codes to `AppStrings` (Section 5.6). The application layer never produces display text.

### 3.3 Workspace API

```dart
final class TaskWorkspace {
  TaskWorkspace({required TaskRepository repository, required Clock clock, required IdGenerator ids});

  Stream<WorkspaceState> get states;   // broadcast; emits after every change
  WorkspaceState get state;

  Future<void> load();

  // Navigation and visibility (all go through the gate, Section 5.4)
  void requestSelectView(SmartView view);
  void requestSelectProject(String projectId);
  void requestSelectTask(String? taskId);      // null clears selection (Esc)
  void requestSearch(String query);
  void requestSort(TaskSort sort);             // sort never hides a task, so no gate needed
  void toggleExpanded(String taskId);          // collapse may hide children; see 5.4 table

  // Creation (creating selects the new task, so it goes through the gate)
  Future<Result<Task, WorkspaceError>> requestCreateRootTask({required String title, required String projectId});
  Future<Result<Task, WorkspaceError>> requestCreateSubtask({required String title, required String parentId});

  // Draft editing (no persistence until saveDraft)
  void editDraft({String? title, TaskStatus? status, TaskPriority? priority, CalendarDate? dueDate, bool clearDueDate = false, String? notes});
  void revertDraft();                          // back to base, not dirty
  Future<Result<void, WorkspaceError>> saveDraft();

  // Gate resolution (only when state.pending != null)
  Future<void> resolvePending(PendingResolution resolution); // save | discard | cancel

  // App exit (Section 5.4)
  Future<bool> requestExit();                  // true = may exit now; false = gate is open
}

sealed class NavSelection {}
final class SmartViewSelection extends NavSelection { SmartViewSelection(this.view); final SmartView view; }
final class ProjectSelection extends NavSelection { ProjectSelection(this.projectId); final String projectId; }

sealed class WorkspaceTransition {}              // what the user asked to do
final class TransitionSelectView extends WorkspaceTransition { TransitionSelectView(this.view); final SmartView view; }
final class TransitionSelectProject extends WorkspaceTransition { TransitionSelectProject(this.projectId); final String projectId; }
final class TransitionSelectTask extends WorkspaceTransition { TransitionSelectTask(this.taskId); final String? taskId; }
final class TransitionSearch extends WorkspaceTransition { TransitionSearch(this.query); final String query; }
final class TransitionCreate extends WorkspaceTransition { TransitionCreate(this.candidate); final Task candidate; } // validated, not yet persisted
final class TransitionExit extends WorkspaceTransition {}

final class PendingTransition { PendingTransition(this.transition); final WorkspaceTransition transition; }
enum PendingResolution { save, discard, cancel }
```

`requestCreateRootTask` and `requestCreateSubtask` validate first. Validation errors return `Err` immediately with no gate and no state change. A valid create builds the candidate `Task` (2.2) and then:
- If no dirty draft exists: persists via `saveTask`, selects the new task, and returns `Ok(task)`. A failed persist returns `Err(saveFailed)` and changes no state.
- If a dirty draft exists: stores `TransitionCreate(candidate)` in `pending`, persists nothing, and returns `Ok(candidate)` with `pending` set. Persistence and selection happen only when the gate resolves with `save` or `discard`.

### 3.4 Architecture rules (replaces v1 controller rule)
- `lib/core/`, `lib/features/*/domain/`, `lib/features/*/application/`: imports limited to `dart:` libraries and this package. No `package:flutter`, no `package:sqlite*`, no `package:supabase*`, no `package:http`.
- `lib/features/*/presentation/` and `lib/app/`: may import Flutter. Must not import any persistence or network package.
- The `ChangeNotifier` adapter `TasksNotifier` lives in presentation. It subscribes to `TaskWorkspace.states` and calls `notifyListeners()`. It contains no business logic.

These rules are enforced by `test/architecture/import_rules_test.dart` (written first in Task 1; extended in Task 2 and Task 3).

---

## 4. Dependencies

**Proposal: no new runtime or dev dependencies in Phase 1.**

| Need | Approach | Why not a package |
|---|---|---|
| State and notification | Pure `TaskWorkspace` + `Stream` (`dart:async`) + `ChangeNotifier` adapter (Flutter SDK) | Keeps application pure; no state-management package until Phase 2 needs one |
| Dates | `CalendarDate` with ISO formatting | Avoids `intl` until localization is needed (later phase) |
| IDs | `Random.secure()` UUID v4 in `lib/core/ids/` | Avoids `uuid` package |
| Keyboard | `Shortcuts`, `Actions`, `Focus` (SDK) | Built in |
| Golden tests | `flutter_test` `matchesGoldenFile` (SDK) | Built in |
| Lifecycle exit request | `AppLifecycleListener.onExitRequested` (SDK) | Avoids a window-management package |

If a package is later approved, it must be exact-pinned (no `^` for new packages), justified in the PR, and locked in the same commit.

---

## 5. UI component hierarchy and interfaces

### 5.1 Presentation adapter
- `TasksNotifier extends ChangeNotifier`: wraps a `TaskWorkspace`; exposes `state`; forwards intents (`requestSelectView` etc.) unchanged.
- `TasksScope` (`InheritedNotifier<TasksNotifier>`) placed above `AppShell`. Widgets read it via `TasksScope.of(context)`.
- No global singletons.

### 5.2 Hierarchy

```
NexoraApp                                    (MaterialApp, dark theme; AppLifecycleListener for exit)
└─ TasksScope
   └─ AppShell                               LayoutBuilder breakpoints (5.7)
      ├─ Shortcuts + Actions (global keymap)  Section 6
      ├─ SidebarNav                          width 240
      │  ├─ SmartViewTile × 4 (count badge)
      │  ├─ SectionHeader "Projects"
      │  └─ ProjectTile × n (count badge)
      ├─ TaskListPane                        flexible width
      │  ├─ TaskListHeader                   view title, result count, "New task" button
      │  ├─ TaskSearchField                  Ctrl+F focuses; Esc clears query
      │  ├─ SortMenu                         position | due date | priority | title
      │  ├─ TaskTree (ListView.builder)
      │  │  └─ TaskRow × n                   indent, chevron, status chip, due label, priority marker, done/total
      │  └─ EmptyState                       no tasks | no matches | empty project
      └─ DetailsPane                         width 360 (overlay below 1100 px)
         ├─ EmptyDetails                     "Select a task"
         └─ TaskDetailsEditor                binds to state.draft only
            ├─ TitleField
            ├─ StatusDropdown                five statuses
            ├─ PriorityDropdown              four priorities
            ├─ DueDateField                  date-only; clear action
            ├─ NotesField                    plain text, multiline
            ├─ ChildSummary                  read-only done/total and "Ready for review" hint
            └─ ActionBar                     Add subtask | Revert | Save
```

Dialogs (presentation only, open from intents):
- `CreateTaskDialog`: title field, project dropdown (preselected to the current project, or the first project in a smart view), Create and Cancel. Enter submits. Inline error from `WorkspaceError`.
- `CreateSubtaskDialog`: title field, parent shown as read-only text, Create and Cancel.
- `UnsavedChangesDialog`: Save, Discard, Cancel, plus an error line when the last save failed (5.4).

### 5.3 Interfaces (summary)
- `SmartViewTile({required SmartView view, required int count, required bool selected, required VoidCallback onTap})`
- `ProjectTile({required Project project, required int count, required bool selected, required VoidCallback onTap})`
- `TaskRow({required VisibleTaskRow row, required bool selected, required VoidCallback onTap, required VoidCallback onToggleExpand})`
- `TaskDetailsEditor({required EditDraft draft, required void Function(DraftEdit edit) onEdit, required VoidCallback onSave, required VoidCallback onRevert, required VoidCallback onAddSubtask})` — stateless; it renders the draft and sends intents. `DraftEdit` is a sealed presentation-side intent type (one case per field: title, status, priority, dueDate, notes) that the presentation maps to `TaskWorkspace.editDraft` arguments. Text controllers are created in a thin `StatefulWidget` wrapper and synced to the draft; the draft in the application layer is the source of truth.

### 5.4 Unsaved-change gate (rewritten in v2)

**Principle:** while a dirty draft exists, any transition that would change the selection, or that would remove the drafted task from the visible list, must be resolved first. The gate lives in `TaskWorkspace`, so every entry point is covered.

**Transition table** (`TaskWorkspace` computes "would hide the draft task" by applying the transition to a copy of the visible-row computation; pure and testable):

| Transition (user action) | Gated when draft is dirty? | Rule |
|---|---|---|
| Select another task (click, ↑/↓, Enter on another row) | Yes | Always, if the new selection differs from the draft's task |
| Clear selection (Esc in list) | Yes | Always |
| Select a smart view | Yes | Only if the drafted task is not visible in the new view (selection would clear) |
| Select a project | Yes | Same rule as smart views |
| Search change (typing) | Yes | Only if the drafted task would become invisible. Typing that keeps it visible is not gated |
| Sort change | No | Sort never hides a task |
| Expand / collapse | No | Collapse that hides the selected row keeps the selection; the details pane still shows the draft and the list shows "Selected task is hidden in this view" |
| Create root task / subtask (success path) | Yes | Creation selects the new task |
| Revert | No | Discards the draft explicitly (user intent) |
| Exit the app (close button, Alt+F4, `AppLifecycleListener.onExitRequested`) | Yes | Always, if dirty |

**Gate behavior:**
1. The transition is stored in `state.pending`; the state does not change yet.
2. `UnsavedChangesDialog` is shown.
3. `resolvePending(save)`: call `saveDraft()`.
   - Success: clear the draft, apply the pending transition, clear `pending`.
   - Failure (`RepositoryException` or validation error): **keep the draft, keep `pending`, set `error`** (`saveFailed` or the validation code). The transition does **not** happen. The dialog stays open with the error line, so the user can retry, discard explicitly, or cancel.
4. `resolvePending(discard)`: **transactional, owner-approved exception (2026-11-12).** The Discard choice is committed only when the pending transition succeeds.
   - Success (pending create): the previous draft is discarded, the new task is committed, selection moves to it, and `pending` is cleared.
   - Failure (persistence error, or the parent was archived in the draft and re-checked at commit): the dirty draft, the selection and `pending` are all preserved, `error` is set, and nothing is added to `tasks`. The dialog shows the error and offers retry (Discard again) or Cancel.
   - Cancel after a failure restores the previous editing context with every edit kept.
   - Duplicate and concurrent use is refused, not executed twice: while a transition or save is running, a second resolution, save, create or edit returns `operationInProgress` (or is ignored for edits).
   - For non-create pending transitions (selection, search, exit) Discard has no persistence step and always succeeds.
   - Save path: `save` persists the draft first, because that is the user's explicit request. If the pending transition then fails, the saved draft stays saved and the pending transition is kept for retry or Cancel. No edit is lost.
5. `resolvePending(cancel)`: clear `pending`; nothing else changes.
6. `requestExit()` while the gate would be needed: sets `pending` to `TransitionExit`, returns `false`. `AppLifecycleListener.onExitRequested` returns `AppExitResponse.cancel`, the dialog shows, and on resolution `save` or `discard` the workspace returns `true` and the presentation calls `exit` / lets the exit proceed.

**Failed-save invariants (tested):**
- A failed save never clears the draft.
- A failed save never changes selection, view, project, search or expansion.
- A failed save never closes the dialog silently.
- A failed create never adds a task to `state.tasks` and never changes selection. The create dialog keeps the title text.

### 5.5 Create and subtask behavior
- **Create root task** (`Ctrl+N` or "New task" button): dialog → `requestCreateRootTask`. On success the workspace selects the new task (through the gate), expands nothing (root), and presentation focuses the details title. Project preselection: the current `ProjectSelection`, or the first project in a smart view.
- **Add subtask** (`Ctrl+Shift+N` or "Add subtask" in ActionBar): enabled only when the selected task is not `archived`. Dialog → `requestCreateSubtask`. On success the parent is expanded, the new child is selected (through the gate), and its title is focused.
- Validation messages (empty, too long, unknown parent, archived parent) are shown inline in the dialog from `WorkspaceError`.
- Creation never changes a parent's status (Section 2.2 rule 7).

### 5.6 Centralized UI strings
- All user-visible text lives in `lib/features/tasks/presentation/strings/app_strings.dart` as `static const` members of `class AppStrings`. Example: `AppStrings.newTask`, `AppStrings.titleRequired`, `AppStrings.errorSaveFailed`.
- `WorkspaceError` codes are mapped to strings in one function, `AppStrings.errorMessage(WorkspaceError)`.
- Dates are formatted by `CalendarDate.toIsoString()`; no locale-dependent formatting in Phase 1.
- Architecture test `test/architecture/strings_test.dart` scans `lib/features/*/presentation/**/*.dart` (excluding `strings/`) and fails on visible-text literals: `Text('`, `hintText: '`, `labelText: '`, `tooltip: '`, `title: '` on text widgets. Tests assert on `AppStrings` constants.

### 5.7 Responsive behavior
- Width ≥ 1100 px: three panes.
- 900–1099 px: details pane becomes a right overlay with a close button that goes through the gate.
- < 900 px: unsupported in Phase 1; show `AppStrings.desktopOnlyNotice` and keep the list usable.

---

## 6. Keyboard and accessibility

### 6.1 Keymap
| Keys | Action | Gated? |
|---|---|---|
| ↑ / ↓ | Move selection through visible rows | Yes (selection change) |
| → / ← | Expand / collapse selected row (← on a collapsed or leaf row moves to parent) | No |
| Enter | Focus details title (on a selected row) | No |
| Esc | Clear selection (in list) / leave editor focus to list | Yes (clear) |
| Ctrl+F | Focus search | No |
| Ctrl+N | New task dialog | Yes (on success) |
| Ctrl+Shift+N | New subtask dialog for selected task | Yes (on success) |
| Ctrl+S | Save draft (when dirty) | Save path (5.4) |
| Ctrl+Z (in editor) | Standard text undo | No |

The keymap is defined once in `lib/features/tasks/presentation/keymap.dart` and wired with `Shortcuts` and `Actions`.

### 6.2 Accessibility fundamentals
- Every interactive element has a text label or a `Semantics` label.
- Focus order follows visual order: sidebar, list header, list, details.
- Visible focus ring on every focusable control.
- Status and priority use text, not color alone.
- Contrast: body text ≥ 4.5:1, large text ≥ 3:1 (tested via `palette.dart` token pairs).
- Text scale 1.3 must not overflow (widget test).
- Minimum hit target 40 × 40 logical px for row actions (desktop pointer).

---

## 7. Theme
- `lib/features/tasks/presentation/theme/palette.dart`: named color tokens for the dark theme (background, surface, surface-2, border, text-1, text-2, text-muted, primary, positive, negative, warning). Fixed constants.
- `lib/app/theme.dart`: `ThemeData` with `brightness: Brightness.dark`; `NexoraApp` sets `ThemeMode.dark`.
- Light theme deferred (decision 7).

---

## 8. Tasks (red → green, one commit per task, mapped to PRs)

Every task: write failing tests first, run them red, implement the minimum, run green, then run `dart format --output=none --set-exit-if-changed .` and `flutter analyze`. Commits follow the Phase 0 style. A red commit is allowed only where the plan says so, and CI is expected to be red on that commit only.

| Task | PR | Summary |
|---|---|---|
| 1 | PR 1 | Domain model, creation rules, validation, ordering, smart views, import-rule test |
| 2 | PR 2 | Pure application: repository, `TaskWorkspace`, demo data, gate, create operations |
| 3 | PR 3 | Presentation adapter `TasksNotifier`, shell, sidebar, `strings/`, Phase 0 test change |
| 4 | PR 4 | Task tree, search, sort, empty states |
| 5 | PR 5 | Details editor bound to draft, save/revert, create and subtask dialogs, unsaved gate UI, exit gate |
| 6 | PR 6 | Keymap and keyboard tests |
| 7 | PR 7 | Responsive overlay, palette tokens, accessibility and contrast tests |
| 8 | PR 8 | Golden tests and CI changes |
| 9 | PR 8 | Acceptance evidence and docs |

### Task 1: Domain model and rules (PR 1)
**Files:** create `lib/core/result.dart`, `lib/core/ids/id_generator.dart`, `lib/core/ids/random_id_generator.dart`, `lib/features/tasks/domain/task_priority.dart`, `calendar_date.dart`, `clock.dart`, `task.dart`, `project.dart`, `task_tree_rules.dart`, `task_creation_rules.dart`, `task_validation.dart`, `task_completion_tree.dart`, `smart_view.dart`, `task_ordering.dart`, `task_search.dart`; tests under `test/features/tasks/domain/` (one per source file) and `test/architecture/import_rules_test.dart`.

**Interfaces:** as Section 2. `Result<T, E>` is `sealed class Result<T, E>` with `Ok` and `Err`.

**Architecture test (written first):** scans `lib/core/**`, `lib/features/*/domain/**` and `lib/features/*/application/**` for `import 'package:` lines other than `package:nexora/`, and for any `package:flutter`, `package:sqlite`, `package:supabase`, `package:http`. Scans presentation for the same persistence and network packages.

**Acceptance:** all Section 2.6 tests pass; import-rule test passes; `RandomIdGenerator` produces 36-character v4 UUIDs (test with a regex).

**Red/green:** commit 1 = tests only (CI red by design). Commit 2 = implementation (green).

**Commits:** `test: specify task domain, creation and smart view rules` → `feat: implement task domain and creation rules`.

**Risks:** date boundary bugs. Mitigation: `CalendarDate` has no time zone; only `SystemClock` converts from `DateTime`.

### Task 2: Pure application workspace (PR 2)
**Files:** create `lib/features/tasks/application/task_repository.dart`, `repository_exception.dart`, `in_memory_task_repository.dart`, `demo_data.dart`, `task_workspace.dart`, `workspace_state.dart`, `edit_draft.dart`, `nav_selection.dart`, `workspace_transition.dart`, `workspace_error.dart`, `visible_task_row.dart`; tests under `test/features/tasks/application/` (fake repository with `failNextSave` and `failNextLoad`).

**Acceptance:**
- `load()` populates projects and tasks; a load failure sets `WorkspaceError.loadFailed` and keeps the workspace empty.
- `requestCreateRootTask` and `requestCreateSubtask`: success selects the new task and persists via `saveTask`; each validation error returns the matching `WorkspaceError` without touching state or repository.
- Create on a dirty draft goes to `pending` and does not persist until resolved.
- Gate: every row of the Section 5.4 table has a test (gated / not gated), including "search that keeps the task visible is not gated".
- Failed save during gate `save`: draft kept, `pending` kept, selection unchanged, `error = saveFailed`. Same for failed create.
- `resolvePending(discard)` applies the pending transition; `cancel` clears only `pending`.
- `requestExit()` returns `false` and sets `pending` when dirty; `true` when clean.
- Saving a valid draft updates `tasks`, `visibleRows` and counts; ordering is per Section 2.3.
- Completing all children does not change the parent's status (Phase 0 regression, at workspace level).
- Demo data is deterministic for a given `Clock` (same IDs, titles, dates).
- Import-rule test: `task_workspace.dart` and every application file contain no `package:flutter`.

**Red/green:** commit 1 = tests (CI red). Commit 2 = implementation (green).

**Commits:** `test: specify pure workspace, gate and creation behavior` → `feat: add pure task workspace with unsaved-change gate`.

**Risks:** the gate grows complex. Mitigation: the "would hide" computation is one pure function with a table test; transitions are a sealed class so the compiler lists every case.

### Task 3: Presentation adapter, shell and sidebar (PR 3)
**Files:** create `lib/features/tasks/presentation/tasks_notifier.dart`, `tasks_scope.dart`, `strings/app_strings.dart`, `lib/app/app_shell.dart`, `sidebar_nav.dart`, `smart_view_tile.dart`, `project_tile.dart`; modify `lib/app/nexora_app.dart` (wrap in `TasksScope`, use `AppShell`, add `AppLifecycleListener`), `lib/main.dart` (wire `SystemClock`, `RandomIdGenerator`, `InMemoryTaskRepository` with demo data).

**Acceptance:**
- `TasksNotifier` forwards each intent to `TaskWorkspace` and calls `notifyListeners()` on every state emission (unit test with a fake stream).
- Three panes at ≥ 1100 px (widget test with fixed surface size).
- Sidebar tap on each smart view and project updates the header and counts; counts equal workspace counts.
- Strings test (Section 5.6) passes for files in this PR.
- Phase 0 test `test/app/nexora_app_test.dart` is updated: "Offline ready" is replaced by the shell's text. This change is called out in the PR body and needs explicit owner approval.

**Commits:** `test: specify notifier forwarding and shell navigation` → `feat: add three-pane shell and sidebar navigation`.

**Risks:** the Phase 0 test change. Mitigation: a separate commit with the old assertion kept in the commit message; owner approval required.

### Task 4: Task tree, search, sort, empty states (PR 4)
**Files:** create `task_tree_list.dart`, `task_row.dart`, `task_list_header.dart`, `task_search_field.dart`, `sort_menu.dart`, `empty_state.dart`; modify `app_shell.dart`.

**Acceptance:**
- Rows show indentation, chevron (only with children), status chip (text), due label, priority marker (text), and `done/total` for parents.
- Expand/collapse updates visible rows; collapsed children are not built.
- Search narrows rows and count; "No tasks match your search" with Clear.
- Sort menu reorders deterministically (Section 2.3).
- Empty project: "No tasks in this project yet".
- Parent with all children done shows the "Ready for review" hint and keeps its status.
- Search and sort do not trigger the gate unless the draft becomes hidden (gate behavior is covered in Task 2; Task 4 widget tests verify the dialog appears in that case once Task 5 wires it — until then, the gate can be exercised through the workspace test only).

**Commits:** `test: specify task tree rendering, search and sort` → `feat: render task tree with search, sort and empty states`.

**Risks:** large trees. Mitigation: `ListView.builder` with a test asserting only visible rows are built (count-based, not timing-based).

### Task 5: Details editor, creation dialogs, unsaved-change UI, exit gate (PR 5)
**Files:** create `task_details_editor.dart`, `task_details_pane.dart`, `status_dropdown.dart`, `priority_dropdown.dart`, `due_date_field.dart`, `notes_field.dart`, `child_summary.dart`, `create_task_dialog.dart`, `create_subtask_dialog.dart`, `unsaved_changes_dialog.dart`; modify `app_shell.dart`, `nexora_app.dart` (exit listener).

**Acceptance:**
- Editing a field updates the draft in the workspace; Save and Revert enable only when dirty.
- Empty title shows `AppStrings.titleRequired`; save is blocked by validation and the draft is kept.
- Revert restores base values.
- Due date: date-only picker and clear action; displayed as ISO `YYYY-MM-DD`.
- Save success updates the row in the list.
- "Add subtask" disabled for archived tasks; creating a subtask expands the parent and selects the child.
- `CreateTaskDialog`: Enter submits; validation error text shown; on success dialog closes and the new task is selected.
- Unsaved dialog appears for every gated transition in Section 5.4 (widget tests for select task, select view, select project, search that hides the draft, create, exit).
- Failed save in the dialog keeps it open with `AppStrings.errorSaveFailed`; the underlying transition does not happen.
- Discard applies the transition and discards the draft; Cancel leaves everything unchanged.

**Commits:** `test: specify editor, creation dialogs and unsaved-change UI` → `feat: add details editor, creation dialogs and unsaved-change gate UI`.

**Risks:** text controllers drifting from the draft. Mitigation: controllers are rebuilt from the draft when the draft's `taskId` changes; a widget test edits, saves and reselects.

### Task 6: Keyboard navigation (PR 6)
**Files:** create `keymap.dart`, `keyboard_actions.dart`; modify `tasks_scope.dart`, `task_tree_list.dart`, `app_shell.dart`, `task_search_field.dart`.

**Acceptance:** every keymap row in Section 6.1 has a keyboard test (`sendKeyEvent`) with no pointer. Gated keys route through the same gate as clicks (test: ↑ with a dirty draft opens the dialog).

**Commits:** `test: specify keyboard navigation and gated shortcuts` → `feat: add keyboard navigation and shortcuts`.

**Risks:** focus traps. Mitigation: a focus test per keymap entry.

### Task 7: Responsive overlay, palette, accessibility checks (PR 7)
**Files:** create `theme/palette.dart`, `lib/app/theme.dart`, `details_overlay.dart`; tests `test/features/tasks/presentation/accessibility_test.dart`, `contrast_test.dart`.

**Acceptance:**
- At 1000 px, details appear as an overlay; closing it goes through the gate; focus returns to the list.
- Text scale 1.3: no overflow in list, sidebar and details (widget test).
- Contrast ratios for all text token pairs ≥ 4.5:1 (unit test).

**Commits:** `test: specify responsive overlay and accessibility checks` → `feat: add responsive overlay, palette tokens and accessibility fixes`.

### Task 8: Golden tests and CI changes (PR 8)
**Files:** create `test/golden/shell_golden_test.dart` (two goldens: All view with a selection; empty state); add `test/golden/goldens/*.png`; modify `.github/workflows/ci.yml` only if decision 9 requires it.

**Acceptance:** goldens match on `windows-latest` with pinned Flutter; format, analyze, test, build and ZIP smoke gates unchanged from Phase 0.

**Commits:** `test: add shell golden tests` → `ci: run golden tests on pinned Windows runner`.

**Risks:** golden drift across fonts. Mitigation: goldens only from the pinned runner (decision 9); regenerate via a one-shot workflow on `main`.

### Task 9: Acceptance evidence and docs (PR 8)
**Files:** update `README.md` (Phase 1 features, keymap); create `docs/operations/phase-1-acceptance.md`.

**Commits:** `docs: record Phase 1 acceptance evidence`.

---

## 9. Owner decisions (resolved in principle, v2 status)

| # | Decision | Resolution |
|---|---|---|
| 1 | Deadline type | Date-only `CalendarDate` |
| 2 | Next 7 Days | Tomorrow through today+7 inclusive |
| 3 | Notes format | Plain text |
| 4 | Create and delete | Create task and subtask: **yes**; delete: **no** |
| 5 | Locale | English UI strings, ISO dates; centralized in `AppStrings` |
| 6 | Priority values | `none, low, medium, high` |
| 7 | Light theme | Deferred |
| 8 | Minimum width | 900 px with overlay for details below 1100 px |
| 9 | Golden files | Generated on the pinned `windows-latest` runner |
| 10 | Parent review state | Derived hint only; status never written automatically |
| 11 | Search scope | Title and notes, case-insensitive substring |
| 12 | Archived tasks | Hidden in Today, Next 7 Days and Overdue; shown in All with a chip |

---

## 10. Verification strategy

| Layer | What | Where | Gate |
|---|---|---|---|
| Domain regression | Rules, creation, completion, smart views, ordering, search | `test/features/tasks/domain/` | `flutter test` |
| Application | Workspace, gate table, failed-save invariants, create operations, parent-completion regression | `test/features/tasks/application/` | `flutter test` |
| Presentation adapter | Notifier forwarding | `test/features/tasks/presentation/` | `flutter test` |
| Widget | Shell, sidebar, tree, search, sort, empty states, editor, creation dialogs, unsaved dialog | `test/features/tasks/presentation/` | `flutter test` |
| Keyboard | Keymap with `sendKeyEvent`; gated keys | `keyboard_test.dart` | `flutter test` |
| Accessibility | Contrast, text scale 1.3, semantics labels | `accessibility_test.dart`, `contrast_test.dart` | `flutter test` |
| Golden | Two shell goldens | `test/golden/` | `flutter test` on pinned runner |
| Architecture | Import rules for core, domain, application, presentation | `test/architecture/import_rules_test.dart` | `flutter test` |
| Strings | No visible-text literals in presentation outside `strings/` | `test/architecture/strings_test.dart` | `flutter test` |
| Format and analyze | Pinned formatter and analyzer | CI | `dart format --set-exit-if-changed`, `flutter analyze` |
| Build and ZIP | Windows release bundle and portable ZIP | CI | `tool/package_windows.ps1` |
| Smoke | Extract to a path with spaces and non-ASCII, launch, close with exit 0 | CI (Phase 0 script) | same |
| Exact-HEAD CI | Green on the final PR commit SHA | GitHub Actions | required before merge |

**Manual check (owner, not a gate):** run the extracted ZIP on a Windows 10 x64 machine; confirm keymap, dark theme, the unsaved dialog on exit, and a create-then-subtask flow. Record in the acceptance doc.

---

## 11. Phase 1 acceptance checklist

- [ ] Domain rules, creation rules, completion semantics and smart views pass their regression tests.
- [ ] Parent closure is manual: no test or UI path writes a parent status from its children, including after subtask creation.
- [ ] Create task and create subtask work with validation, deterministic ordering and tests (creation order preserved).
- [ ] No delete path exists in UI or application code (test or grep).
- [ ] Three-pane shell at ≥ 1100 px; overlay at 900–1099 px.
- [ ] Sidebar: Today, Next 7 Days, Overdue, All, Projects, with correct counts.
- [ ] Tree: deterministic order, expand/collapse, `done/total`, "Ready for review" hint.
- [ ] Search, sort, empty states, clear-selection behavior work as specified.
- [ ] Unsaved-change gate covers every transition in the Section 5.4 table, including exit; failed saves keep the draft and block navigation.
- [ ] Keyboard map in Section 6 works without a pointer.
- [ ] Dark theme default; contrast tests pass; text scale 1.3 does not overflow.
- [ ] Import-rule test: no persistence or network package in `lib/`; no Flutter import in `core`, `domain` or `application`.
- [ ] Strings test: no visible-text literals in presentation outside `strings/`.
- [ ] No new dependency, or each new dependency is approved, exact-pinned and justified.
- [ ] Format, analyze, tests, Windows build, ZIP build and smoke test pass on the exact final HEAD.
- [ ] Portable ZIP attached to the final CI run; smoke-test output recorded.
- [ ] Owner reviews the running ZIP and approves the UI before merge.

---

## 12. PR breakdown

Each PR is a Draft until the owner approves it. Each is merged only with owner approval.

| PR | Tasks | Depends on | Notes |
|---|---|---|---|
| 0 | This plan (v2) | — | Reviewed and merged first |
| 1 | Task 1 | PR 0 merged | Pure domain |
| 2 | Task 2 | PR 1 | Pure application workspace |
| 3 | Task 3 | PR 2 | Adapter, shell; Phase 0 test change needs explicit approval |
| 4 | Task 4 | PR 3 | Tree, search, sort |
| 5 | Task 5 | PR 4 | Editor, creation dialogs, gate UI, exit gate |
| 6 | Task 6 | PR 5 | Keyboard |
| 7 | Task 7 | PR 5 | Overlay, palette, accessibility (may run parallel with PR 6) |
| 8 | Tasks 8 and 9 | PR 6 and 7 | Goldens, CI, acceptance |

Execution order: 0 → 1 → 2 → 3 → 4 → 5 → {6, 7} → 8.

---

## 13. Risks and rollback

| Risk | Impact | Mitigation | Rollback |
|---|---|---|---|
| Gate misses a transition | High (lost edits) | Transition table tests; sealed transition class forces exhaustive handling | Revert the PR that added the path; draft stays in application state |
| Failed save clears or loses draft | High | Invariant tests (Task 2 and 5) | Revert PR 5 |
| Phase 0 test change hides regression | Medium | Owner approval; separate commit | Revert PR 3's test commit |
| Date off by one | High | `CalendarDate` with no time zone; boundary tests | Revert PR 1 |
| Golden flakiness across fonts | Medium | Goldens only from pinned runner | Drop goldens; keep widget tests |
| Keyboard focus trap | Medium | Focus test per keymap entry | Disable one shortcut in `keymap.dart` |
| Scope creep (delete, persistence) | High | Section 1 out-of-scope list; PR review | Owner review each PR |
| Exit gate unreliable on Windows | Medium | `AppLifecycleListener` tested via a widget test; manual ZIP check | Fall back to in-app close button only; document limitation |

Each PR is independently revertible. Phase 2 starts from `TaskRepository`, so the in-memory implementation is replaced without changing the workspace or UI.

---

## 14. Next implementation step

After this plan is merged (owner approval): create `feature/phase-1-domain` from `main`, and execute Task 1 (red commit, then green commit) as described in the Task 1 implementation proposal. No other Phase 1 feature work starts before PR 1 is approved.
