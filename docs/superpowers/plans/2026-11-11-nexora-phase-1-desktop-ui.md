# Nexora Phase 1 — Desktop UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Do not start implementation until the owner approves this plan and resolves the open decisions in Section 9.**

**Goal:** Build a modern, dark, three-pane Windows desktop UI over deterministic in-memory demo data. Implement smart views, projects, a recursive task tree, a details editor, search, sorting, keyboard navigation and accessibility fundamentals, with clean boundaries for the Phase 2 SQLite repository.

**Architecture:** Feature-first layers. Pure Dart domain (no Flutter, no database). An application layer (`TasksController`, a `ChangeNotifier`) talks to an async `TaskRepository` interface. The only repository in Phase 1 is an in-memory implementation over demo data. Widgets are presentation-only and read controller state.

**Tech Stack:** Flutter 3.47.9 (stable) / Dart 3.13.7, pinned in CI as in Phase 0. flutter_test, flutter_lints. No new runtime dependencies (see Section 4).

**Predecessors:**
- Spec: [docs/superpowers/specs/2026-11-11-nexora-v1-design.md](../specs/2026-11-11-nexora-v1-design.md)
- Phase 0 plan (merged in PR #2, merge commit `a05b353`): [docs/superpowers/plans/2026-11-11-nexora-phase-0-foundation.md](2026-11-11-nexora-phase-0-foundation.md)
- ADR: [docs/architecture/decisions/0001-flutter-offline-first.md](../../architecture/decisions/0001-flutter-offline-first.md)
- Sync contract: [docs/architecture/sync-contract.md](../../architecture/sync-contract.md)

---

## 0. Reconciliation with existing decisions

Verified on `main` at `a05b353`:

| Item | Status | Phase 1 decision |
|---|---|---|
| `TaskStatus { open, inProgress, review, done, archived }` | Exists (`lib/features/tasks/domain/task_status.dart`) | Reused unchanged |
| `summarizeChildren` / `TaskCompletion` (direct children only, `eligibleForReview` never sets `done`) | Exists (`task_completion.dart`) | Reused unchanged; recursion is added as a separate projection, so Phase 0 semantics stay intact |
| Parent completion: manual closure, derived review hint | Phase 0 test `task_completion_test.dart` | Preserved. The UI shows a hint; it never persists a parent status change |
| Supabase access: verified read-only, no hosted writes | `docs/operations/supabase-access.md` | Phase 1 has no Supabase code and no network |
| Phase 1 plan file | Named in Phase 0 plan's "Subsequent Plans" list | This file. No earlier Phase 1 plan exists on `main` or any remote branch |
| `TaskRepository` / `TaskPriority` / `Task` / `CalendarDate` | Do not exist | Created in Phase 1 |
| Spec: "display in device timezone; date-only vs timestamp deadlines" | Open | Phase 1 uses date-only `CalendarDate` (decision 1) |

No duplicate work is planned. Phase 1 adds to the Phase 0 domain and does not change it.

---

## 1. Scope

### In scope
- Three-pane shell: left navigation, center task list, right details editor.
- Left navigation: Today, Next 7 Days, Overdue, All, and a Projects section.
- Project filtering and smart-view filtering with live counts.
- Center pane: recursive task tree with deterministic sibling ordering, expand/collapse, completion summary per parent.
- Right pane: edit title, status, priority, due date (date-only), and plain-text notes. Explicit Save and Revert. Unsaved-change guard on selection change.
- Search (title and notes, case-insensitive), sorting (position, due date, priority, title), empty states, clear-selection behavior.
- Dark theme by default.
- Keyboard navigation and accessibility fundamentals (focus order, semantics labels, contrast, text scaling).
- Deterministic demo data (fixed IDs, fixed dates relative to an injected clock).
- Tests: domain, controller, widget, keyboard, golden (limited), and the existing CI gates.

### Out of scope (Phase 1)
- SQLite, persistence of edits across restarts, autosave (Phase 2).
- Supabase, auth, sync, conflicts, RLS (Phase 3).
- Reminders, tray, notifications, export/import, portable-release acceptance beyond the Phase 0 ZIP gate (Phase 4).
- Light theme (decision 7), task deletion (decision 4), rich-text or markdown notes (decision 3), multi-workspace and sharing.

---

## 2. Domain model (pure Dart)

All files under `lib/features/tasks/domain/`. No `package:flutter` imports.

| Type | Kind | Notes |
|---|---|---|
| `TaskStatus` | enum (exists) | `open, inProgress, review, done, archived` |
| `TaskPriority` | enum (new) | `none, low, medium, high` (decision 6) |
| `CalendarDate` | value class (new) | `year, month, day`; comparison; `addDays`; no time zone. Avoids `DateTime` local-midnight drift |
| `Clock` | abstract interface (new) | `CalendarDate today()`. Production: local date from `DateTime.now()`. Tests: fixed date |
| `Task` | immutable class (new) | `id, projectId, parentId?, title, status, priority, dueDate?, notes, position`; `copyWith` |
| `Project` | immutable class (new) | `id, name, position` |
| `TaskTreeRules` | pure functions (new) | Validate parent changes; see below |
| `TaskCompletion` / `summarizeChildren` | exists | Reused |
| `completionOf(taskId, tasks)` | function (new) | Applies `summarizeChildren` to direct children only, from the task map |
| `SmartView` | enum (new) | `today, next7Days, overdue, all` |
| `SmartViewRules` | pure functions (new) | `matches(task, view, today)`; see boundaries below |
| `TaskOrdering` | pure functions (new) | Deterministic sibling and flat-list order |
| `TaskSearch` | pure function (new) | Case-insensitive substring over title and notes |

### Rules

**Parent change validation** (`TaskTreeRules.validateParentChange`): returns `ParentChangeResult.ok` or one of `selfParent`, `cycle`, `crossProject`, `missingParent`. It is checked on every save that changes `parentId`.

**Recursive completion** (`completionOf`): direct children only, as in Phase 0. Grandchildren do not change a parent's counts directly; a child with its own children shows its own completion summary when that child is inspected. A parent's status is never written by this projection.

**Smart views** (all use `today` from the injected `Clock`):
- `today`: `dueDate == today`, status not `done` or `archived`.
- `next7Days`: `today < dueDate <= today + 7`, status not `done` or `archived` (decision 2).
- `overdue`: `dueDate < today`, status not `done` or `archived`.
- `all`: every task, including archived, shown with an "archived" chip (decision 12).

**Ordering:** siblings sort by `position`, then by `id` as a tie-breaker. The flat list is a depth-first walk over roots and children in that order. Sort options (`position`, `dueDate`, `priority`, `title`) reorder siblings only when a sort other than `position` is selected; the tie-breaker `id` stays fixed.

### Domain tests (written first, Task 1)
- `CalendarDate`: ordering, `addDays` across month and year boundaries, leap day.
- `TaskTreeRules`: self-parent rejected; cycle (A→B→C, set A's parent to C) rejected; cross-project parent rejected; missing parent rejected; valid move accepted.
- `completionOf`: parent with children `[done, done]` → eligible, status unchanged; grandchild completion does not change the parent's direct counts; no children → not eligible.
- `SmartViewRules`: boundary table with a fixed `today` (today, today+1, today+7, today+8, yesterday, done task, archived task) for each view.
- `TaskOrdering`: stable across repeated calls; tie-break by id; sort by due date places tasks without a due date last.
- `TaskSearch`: case-insensitive; matches notes; empty query matches all.

---

## 3. Application layer

All files under `lib/features/tasks/application/`.

```dart
// Async from the start so a Phase 2 SQLite implementation is a drop-in.
abstract interface class TaskRepository {
  Future<List<Project>> loadProjects();
  Future<List<Task>> loadTasks();
  Future<void> saveTask(Task task);
}

// Phase 1 only. Seeded from demo_data.dart with fixed IDs and dates.
final class InMemoryTaskRepository implements TaskRepository { ... }

sealed class NavSelection {}
final class SmartViewSelection extends NavSelection { SmartViewSelection(this.view); final SmartView view; }
final class ProjectSelection extends NavSelection { ProjectSelection(this.projectId); final String projectId; }

final class TasksController extends ChangeNotifier {
  TasksController({required TaskRepository repository, required Clock clock});

  // Read state
  List<Project> get projects;
  NavSelection get selection;
  String get searchQuery;
  TaskSort get sort;
  String? get selectedTaskId;
  Set<String> get expandedTaskIds;
  List<VisibleTaskRow> get visibleRows;      // flattened tree for the center pane
  Map<SmartView, int> get smartViewCounts;   // sidebar badges
  Map<String, int> get projectCounts;
  Task? get selectedTask;
  bool get hasUnsavedChanges;                // set by the details editor

  // Actions
  Future<void> load();
  void selectView(SmartView view);
  void selectProject(String projectId);
  void setSearch(String query);
  void setSort(TaskSort sort);
  void selectTask(String? taskId);           // null clears selection
  void toggleExpanded(String taskId);
  Future<ParentChangeResult?> saveTask(Task task);  // validation first; null on success path
}
```

`VisibleTaskRow` is a value class: `task`, `depth`, `hasChildren`, `isExpanded`, `completion`.

**Selection rules:**
- Changing the navigation selection keeps the selected task only if it remains visible in the new view; otherwise it clears.
- `selectTask(null)` clears selection and shows the empty details pane.
- If the details editor has unsaved changes, the controller does not change selection until the UI resolves the guard (Section 5.4). The controller exposes `hasUnsavedChanges` as a flag set by the editor; it does not own the draft.

**Demo data** (`demo_data.dart`): about 3 projects, about 25 tasks, nested to depth 4, covering every status and priority, tasks due today/tomorrow/in 8 days/yesterday, a done parent with all children done, and a parent with mixed children. IDs are fixed strings such as `task-001`. Dates are computed from the injected `Clock` at load time, so tests can pass a fixed clock.

### Application tests (written first, Task 2)
- `load()` populates projects and tasks from the repository (fake repository in tests).
- Selecting a view clears the selection if the selected task is not visible in the new view.
- `saveTask` with an invalid parent returns the rule result and does not call `saveTask` on the repository.
- Saving a valid edit updates `visibleRows` and counts.
- Completing all children does not change the parent's status (Phase 0 regression, at controller level).

---

## 4. Dependencies

**Proposal: no new runtime or dev dependencies in Phase 1.**

| Need | Approach | Why not a package |
|---|---|---|
| State management | `ChangeNotifier` + `ListenableBuilder` (Flutter SDK) | Phase 1 state is small; adding Riverpod/Bloc is a larger decision best deferred to Phase 2 |
| Date formatting | Hand-written `CalendarDate.toIsoString()` and a small label helper | Avoids `intl` until localization is decided (decision 5 covers locale) |
| Keyboard shortcuts | `Shortcuts`, `Actions`, `Focus` (Flutter SDK) | Built in |
| Golden tests | `flutter_test` `matchesGoldenFile` (SDK) | Built in |
| Icons | Material icons (SDK) | Already enabled in pubspec |

If owner approves a package (decision 5 or 8), it must be added with an exact version pin (`^` is not allowed for new packages), a justification in the PR body, and a `pubspec.lock` update in the same commit.

---

## 5. UI component hierarchy and interfaces

```
NexoraApp                                    (exists; sets dark theme and home)
└─ AppShell                                  LayoutBuilder breakpoints (Section 5.5)
   ├─ Shortcuts + Actions (global keymap)    Section 6
   ├─ SidebarNav                             width 240
   │  ├─ SmartViewTile × 4 (Today, Next 7 Days, Overdue, All) with count badge
   │  ├─ SectionHeader "Projects"
   │  └─ ProjectTile × n with count badge
   ├─ TaskListPane                           flexible width
   │  ├─ TaskListHeader                      view title, result count
   │  ├─ TaskSearchField                     Ctrl+F focuses; Esc clears query
   │  ├─ SortMenu                            position | due date | priority | title
   │  ├─ TaskTree (ListView.builder)
   │  │  └─ TaskRow × n                      indent, expand chevron, status chip, due label, priority dot, completion "done/total"
   │  └─ EmptyState                          variants: no tasks, no search matches, empty project
   └─ DetailsPane                            width 360 (or overlay below breakpoint)
      ├─ EmptyDetails                        "Select a task"
      └─ TaskDetailsEditor (StatefulWidget, owns the draft only)
         ├─ TitleField
         ├─ StatusDropdown                   five statuses
         ├─ PriorityDropdown                 four priorities
         ├─ DueDateField                     date-only, clear button
         ├─ NotesField                       plain text, multiline
         ├─ ChildSummary                     read-only "done/total" and "Ready for review" hint
         └─ ActionBar                        Revert | Save; Save disabled when clean
```

### Interfaces (summary)
- `SmartViewTile({required SmartView view, required int count, required bool selected, required VoidCallback onTap})`
- `ProjectTile({required Project project, required int count, required bool selected, required VoidCallback onTap})`
- `TaskRow({required VisibleTaskRow row, required bool selected, required VoidCallback onTap, required VoidCallback onToggleExpand})`
- `TaskDetailsEditor({required Task task, required List<Task> siblingsOrChildren, required Future<ParentChangeResult?> Function(Task) onSave, required ValueChanged<bool> onDirtyChanged})`
- Widgets read `TasksController` through a single `InheritedNotifier` (`TasksScope`) placed above `AppShell`. No global singletons.

### 5.4 Unsaved-change guard
When the editor is dirty and the user selects another task or view, show a dialog: **Save**, **Discard**, **Cancel**. Save runs `saveTask` and then continues the selection change only on success. This is a widget test (Task 7).

### 5.5 Responsive behavior
- Width ≥ 1100 px: three panes.
- 900–1099 px: details pane becomes a right-side overlay with a close button; selection still works.
- < 900 px: not a supported Phase 1 layout. Show a notice "Nexora Phase 1 is designed for desktop widths (900 px or more)" and keep the list usable (decision 8).

---

## 6. Keyboard and accessibility

### Keymap
| Keys | Action |
|---|---|
| ↑ / ↓ | Move selection through visible rows |
| → / ← | Expand / collapse selected row (or move to parent on ←) |
| Enter | Focus the details title field |
| Esc | Clear selection (if no unsaved changes); otherwise cancel focus in the editor |
| Ctrl+F | Focus search |
| Ctrl+S | Save draft (when dirty) |
| Ctrl+Z (in editor) | Standard text undo; no custom app undo in Phase 1 |

Shortcuts are defined once in `lib/features/tasks/presentation/keymap.dart` and wired with `Shortcuts` and `Actions`, so they can be tested without pointing devices.

### Accessibility fundamentals
- Every interactive element has a `Semantics` label or a text label.
- Focus order follows the visual order: sidebar, list header, list, details.
- Visible focus ring on every focusable control.
- Status and priority are conveyed by text, not only color.
- Contrast: body text ≥ 4.5:1, large text ≥ 3:1 against the dark surfaces (verified with a fixed palette in `theme/palette.dart` and a unit test that computes the ratios).
- Text scaling: layout must not overflow at text scale factor 1.3 (widget test with `MediaQuery` override).
- Minimum hit target 40 × 40 logical px for row actions (desktop pointer; not 44 as in the mobile rule).

---

## 7. Theme

- `lib/features/tasks/presentation/theme/palette.dart`: named color tokens for the dark theme (background, surface, surface-2, border, text-1, text-2, text-muted, primary, positive, negative, warning). Values are fixed constants.
- `lib/app/theme.dart`: builds `ThemeData` with `brightness: Brightness.dark`, `ThemeMode.dark` set in `NexoraApp`.
- Light theme is deferred (decision 7). The palette structure allows adding it later without touching widgets.

---

## 8. Tasks (red → green, one commit per task)

Every task: write the failing tests first, run them red, implement the minimum, run green, then run `flutter analyze` and `dart format --output=none --set-exit-if-changed .` before committing. Commit message follows the Phase 0 style.

### Task 1: Domain model and rules
**Files:** create `lib/features/tasks/domain/task_priority.dart`, `calendar_date.dart`, `clock.dart`, `task.dart`, `project.dart`, `task_tree_rules.dart`, `task_completion_tree.dart`, `smart_view.dart`, `task_ordering.dart`, `task_search.dart`; tests under `test/features/tasks/domain/` (one test file per source file).

**Interfaces:** as in Section 2. `CalendarDate.fromDateTime(DateTime local)`; `CalendarDate addDays(int)`; `Comparable` ordering.

**Acceptance:**
- All domain tests in Section 2 pass.
- No file in `lib/features/tasks/domain/` imports `package:flutter`. Enforced by a test that greps the source (`test/architecture/domain_imports_test.dart`).

**Red/green:** commit 1 contains tests only, and CI is red on that commit by design. Commit 2 contains implementation and is green.

**Commits:** `test: specify task domain rules and smart views` → `feat: implement task domain rules`.

**Risks:** date edge cases (time zones, DST). Mitigation: `CalendarDate` has no time zone; conversion from `DateTime` happens only in `SystemClock`.

### Task 2: Repository interface, demo data and controller
**Files:** create `lib/features/tasks/application/task_repository.dart`, `in_memory_task_repository.dart`, `demo_data.dart`, `tasks_controller.dart`, `nav_selection.dart`, `visible_task_row.dart`; tests under `test/features/tasks/application/`.

**Acceptance:** all application tests in Section 3 pass; `demo_data` is deterministic for a given `Clock` (test: same clock gives same IDs, titles, dates).

**Commits:** `test: specify tasks controller behavior` → `feat: add in-memory repository and tasks controller`.

**Risks:** controller doing too much. Mitigation: no widget or `Flutter` import in `application/`; a test checks this too.

### Task 3: Shell and sidebar navigation
**Files:** create `lib/app/app_shell.dart`, `lib/features/tasks/presentation/sidebar_nav.dart`, `smart_view_tile.dart`, `project_tile.dart`, `tasks_scope.dart`; modify `lib/app/nexora_app.dart` (wrap in `TasksScope`, use `AppShell`), `lib/main.dart` (construct controller with `SystemClock` and demo repository); tests under `test/app/` and `test/features/tasks/presentation/`.

**Acceptance:**
- Shell shows three panes at ≥ 1100 px width (widget test with a fixed surface size).
- Tapping Today/Next 7 Days/Overdue/All and each project updates the selection and the header title.
- Counts in the sidebar equal the controller's counts.
- `NexoraApp` still shows the text "Nexora" and "Offline ready" is removed in favor of the shell (Phase 0 test updated in this commit; reason recorded in the commit body).

**Commits:** `test: specify shell layout and navigation` → `feat: add three-pane shell and sidebar navigation`.

**Risks:** Phase 0 test `nexora_app_test.dart` asserts "Offline ready". This is an intentional change; the owner must approve the test update explicitly in the PR.

### Task 4: Task tree list, ordering, completion, search, sort, empty states
**Files:** create `task_tree_list.dart`, `task_row.dart`, `task_list_header.dart`, `task_search_field.dart`, `sort_menu.dart`, `empty_state.dart`; modify `app_shell.dart`.

**Acceptance:**
- Rows show depth indentation, expand chevron (only if children exist), status chip with text, due label, priority marker with text, and `done/total` for parents.
- Expanding and collapsing updates visible rows; collapsed children are not built.
- Search narrows rows and header count; empty result shows "No tasks match your search" with a Clear action.
- Sort menu changes order deterministically; tie-break by id.
- Empty project shows "No tasks in this project yet".
- A parent with all children done shows the "Ready for review" hint and keeps its status.

**Commits:** `test: specify task tree rendering and search` → `feat: render task tree with search, sort and empty states`.

**Risks:** performance with deep trees. Mitigation: a widget test with 500 rows and a 16 ms frame budget check is not reliable in CI; use a count-based check that only visible rows are built (`ListView.builder`).

### Task 5: Details editor (edit, save, revert, validation)
**Files:** create `task_details_editor.dart`, `task_details_pane.dart`, `status_dropdown.dart`, `priority_dropdown.dart`, `due_date_field.dart`, `notes_field.dart`, `child_summary.dart`; modify `app_shell.dart`.

**Acceptance:**
- Editing any field makes the editor dirty; Save and Revert become enabled; the controller's `hasUnsavedChanges` is updated.
- Save with an invalid parent change (not reachable in the UI in Phase 1, but guarded) shows the rule message.
- Revert restores the persisted values.
- Due date field accepts a date picker and a clear action; date-only (no time).
- Empty title is rejected with an inline error "Title is required".
- Save updates the list row (title, status, due label) without rebuilding the whole tree.

**Commits:** `test: specify details editor behavior` → `feat: add task details editor with save and revert`.

**Risks:** draft state and controller state diverge. Mitigation: the draft lives only in the editor; on save the editor sends a full `Task` to `saveTask` and the controller is the single source after save.

### Task 6: Keyboard navigation and shortcuts
**Files:** create `lib/features/tasks/presentation/keymap.dart`, `keyboard_actions.dart`; modify `tasks_scope.dart`, `task_tree_list.dart`, `app_shell.dart`, `task_search_field.dart`.

**Acceptance:** all keyboard tests in Section 6 pass (see Section 10). Focus moves to the details title on Enter and back to the list on Esc.

**Commits:** `test: specify keyboard navigation` → `feat: add keyboard navigation and shortcuts`.

**Risks:** Windows key handling differences (Ctrl vs Cmd). Phase 1 is Windows only; Ctrl is used. Cmd mapping is deferred to the mobile/macOS plan.

### Task 7: Unsaved-change guard, responsive overlay, accessibility checks
**Files:** create `unsaved_changes_dialog.dart`, `details_overlay.dart`, `theme/palette.dart`, `lib/app/theme.dart`; tests `test/features/tasks/presentation/accessibility_test.dart`, `contrast_test.dart`.

**Acceptance:**
- Selecting another task with unsaved changes shows the dialog; Save/Discard/Cancel behave as in Section 5.4.
- At 1000 px width, details appear as an overlay; close returns focus to the list.
- No overflow at text scale 1.3 (widget test).
- Contrast ratios for all token pairs used in text are ≥ 4.5:1 (unit test over `palette.dart`).

**Commits:** `test: specify unsaved-change guard and responsive layout` → `feat: add unsaved-change guard, overlay and palette tokens`.

### Task 8: Golden tests and CI gates
**Files:** create `test/golden/shell_golden_test.dart` (two goldens: All view with a selection, and empty state), `test/golden/goldens/*.png`; modify `.github/workflows/ci.yml` only if decision 9 requires it.

**Acceptance:**
- Goldens match on `windows-latest` with the pinned Flutter version.
- CI still runs format, analyze, test, build, and the ZIP smoke test, unchanged from Phase 0.
- ZIP smoke test (Phase 0 script) passes on the Phase 1 build.

**Commits:** `test: add shell golden tests` → `ci: run golden tests on pinned Windows runner`.

**Risks:** golden files generated on a developer machine differ from CI font rendering. Mitigation: generate goldens only on the pinned CI runner (decision 9).

### Task 9: Acceptance evidence and docs
**Files:** update `README.md` (Phase 1 features, keymap), create `docs/operations/phase-1-acceptance.md`.

**Acceptance:** the Phase 1 checklist (Section 11) is filled with evidence links.

**Commits:** `docs: record Phase 1 acceptance evidence`.

---

## 9. Open design decisions (owner approval required)

Each has a recommendation. The plan assumes the recommendation unless the owner says otherwise.

1. **Deadline type:** date-only `CalendarDate` (recommended) vs timestamp with time zone. Spec requires distinguishing them; Phase 1 implements only date-only.
2. **Next 7 Days range:** tomorrow through today+7 inclusive (recommended, so it does not overlap Today) vs today through today+7.
3. **Notes format:** plain text (recommended) vs markdown or rich text.
4. **Create and delete in Phase 1:** add task / add subtask (recommended, minimal, needed to exercise the hierarchy) and no delete (recommended; deletion needs tombstones per the spec). Confirm.
5. **Locale and date formatting:** English labels with ISO dates (recommended; no `intl`) vs Hungarian labels (the owner's working language) with a hand-written formatter. This affects the "no new dependency" plan.
6. **Priority values:** `none, low, medium, high` (recommended) vs a numeric 1–3 scale.
7. **Light theme:** deferred (recommended) vs included in Phase 1.
8. **Minimum width:** 900 px with an overlay for details (recommended) vs 1100 px minimum.
9. **Golden files:** generated on the pinned `windows-latest` runner via a one-shot workflow (recommended) vs no goldens in Phase 1.
10. **Parent review state:** derived hint only, status never written automatically (recommended, matches Phase 0) vs persisting `review` when all children are done.
11. **Search scope:** title and notes, case-insensitive substring (recommended) vs title only.
12. **Archived tasks:** hidden in Today, Next 7 Days, and Overdue; shown in All with a chip (recommended) vs hidden everywhere by default with a toggle.

---

## 10. Verification strategy

| Layer | What | Where | Gate |
|---|---|---|---|
| Domain regression | Rules, completion, smart views, ordering, search | `test/features/tasks/domain/` | `flutter test` |
| Application | Controller behavior, selection, save rules, parent-completion regression | `test/features/tasks/application/` | `flutter test` |
| Widget | Shell, sidebar, tree, search, sort, empty states, editor, guard, overlay | `test/features/tasks/presentation/` | `flutter test` |
| Keyboard | Keymap via `sendKeyEvent` in widget tests | `test/features/tasks/presentation/keyboard_test.dart` | `flutter test` |
| Accessibility | Contrast unit tests, text scale 1.3 overflow, semantics labels | `accessibility_test.dart`, `contrast_test.dart` | `flutter test` |
| Golden | Two shell goldens (decision 9) | `test/golden/` | `flutter test` on pinned runner |
| Architecture | No Flutter imports in domain or application; no SQLite or Supabase imports anywhere | `test/architecture/` | `flutter test` |
| Format and analyze | Pinned formatter and analyzer | CI | `dart format --set-exit-if-changed`, `flutter analyze` |
| Build and ZIP | Windows release bundle and portable ZIP | CI | `tool/package_windows.ps1` |
| Smoke | Extract to a path with spaces and non-ASCII, launch, close with exit 0 | CI (Phase 0 script) | same |
| Exact-HEAD CI | Green on the final commit SHA of the PR | GitHub Actions | required before merge |

**Manual check (owner, not a gate):** run the extracted ZIP on a Windows 10 x64 machine and confirm the keyboard map and dark theme. Record it in the acceptance doc.

---

## 11. Phase 1 acceptance checklist

- [ ] Domain rules, completion semantics and smart views pass their regression tests.
- [ ] Parent closure is manual: no test or UI path writes a parent status from its children.
- [ ] Three-pane shell at ≥ 1100 px; overlay behavior at 900–1099 px.
- [ ] Sidebar: Today, Next 7 Days, Overdue, All, Projects, each with correct counts.
- [ ] Tree: deterministic order, expand/collapse, `done/total`, "Ready for review" hint.
- [ ] Search, sort, empty states, clear-selection behavior work as specified.
- [ ] Details editor: edit, save, revert, validation, date-only due date, unsaved-change guard.
- [ ] Keyboard map in Section 6 works; no pointer needed for core navigation and editing.
- [ ] Dark theme is the default; contrast tests pass; text scale 1.3 does not overflow.
- [ ] No SQLite, Supabase, network, or authentication code in `lib/` (architecture test).
- [ ] No new dependency, or each new dependency is approved, exact-pinned and justified.
- [ ] `dart format`, `flutter analyze`, `flutter test`, Windows build, ZIP build and smoke test pass on the exact final HEAD.
- [ ] Portable ZIP attached to the final CI run; smoke-test output recorded.
- [ ] Owner reviews the running ZIP and approves the UI before merge.

---

## 12. Suggested PR breakdown

Each PR is a Draft until the owner approves it. Each is reviewed separately and merged only with owner approval.

| PR | Tasks | Depends on | Notes |
|---|---|---|---|
| 0 | This plan (docs only) | — | Reviewed first |
| 1 | Task 1 | PR 0 approved | Pure domain; no UI |
| 2 | Task 2 | PR 1 | Controller and demo data |
| 3 | Tasks 3 | PR 2 | Shell and navigation; changes Phase 0 test (explicit approval) |
| 4 | Task 4 | PR 3 | Tree, search, sort |
| 5 | Task 5 | PR 4 | Editor |
| 6 | Task 6 | PR 5 | Keyboard |
| 7 | Task 7 | PR 5 | Guard, overlay, palette (can run parallel with PR 6 after PR 5) |
| 8 | Task 8 and 9 | PR 6 and 7 | Goldens, CI, acceptance docs |

Execution order: 0 → 1 → 2 → 3 → 4 → 5 → {6, 7} → 8.

---

## 13. Risks and rollback

| Risk | Impact | Mitigation | Rollback |
|---|---|---|---|
| Phase 0 test change in PR 3 hides a regression | Medium | Owner approves the test change explicitly; diff reviewed | Revert PR 3 commit; Phase 0 test restored |
| Date logic off by one | High (wrong smart views) | `CalendarDate` with no time zone; boundary table tests | Revert the domain PR; demo data is in-memory only |
| Golden flakiness across fonts | Medium | Goldens only from the pinned runner (decision 9) | Drop goldens; keep widget tests |
| Keyboard focus traps | Medium | Focus tests per keymap entry | Keymap is isolated in `keymap.dart`; disable without touching widgets |
| Draft/controller divergence | High (lost edits) | Editor owns draft; single save path; guard tests | Revert PR 5 |
| Scope creep (create, delete, persistence) | High | Section 1 out-of-scope list; decision 4 | Owner review at each PR |
| Windows-only behavior assumptions (Ctrl keys, 900 px) | Low | Stated as Windows-only in README | — |

Every PR is independently revertible because each task only adds files or changes the shell wiring in one place. Phase 2 starts from `TaskRepository`, so the in-memory repository can be replaced without UI changes.

---

## 14. Next implementation step

After owner approval of this plan and of decisions 1–12: create `feature/phase-1-domain` from `main`, and execute Task 1 (red commit, then green commit). No other Phase 1 work starts before PR 1 is approved.
