# Nexora Phase 0 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a reproducible, testable Flutter Windows desktop project without changing Supabase or deploying any application code.

**Architecture:** Flutter app with feature-first boundaries and a pure domain module. Phase 0 includes scaffolding, quality gates, documentation, an offline-first architecture contract and portability feasibility checks, but no hosted migrations or live authentication. Subsequent phases implement UI, SQLite, sync and release in that order.

**Tech Stack:** Flutter stable / Dart (pin exact SDK on implementation day), Windows runner, flutter_test, flutter_lints, GitHub Actions (Windows runner), Git.

**Spec:** [docs/superpowers/specs/2026-11-11-nexora-v1-design.md](../specs/2026-11-11-nexora-v1-design.md)

## Execution Amendments (owner-approved, 2026-11-11)
The owner approved this plan with the following amendments. Where they conflict with the task steps below, the amendment applies.
- **SDK location:** Flutter 3.47.9 stable / Dart 3.13.7 is used on CI only. Task 1 Step 1 `flutter doctor -v` on the owner's machine is replaced by the CI job's `flutter --version` output and a Windows toolchain check on the runner.
- **Scaffold generation:** `flutter create` runs in a temporary CI workflow (`scaffold-once`) and its output is committed. No SDK is installed locally.
- **Supabase gate (Task 5):** access is verified and recorded as PASS. The earlier BLOCKED statements are superseded. See `docs/operations/supabase-access.md`.
- **Action pinning:** third-party GitHub Actions are pinned to commit SHAs.
- **TDD:** where a task's red and green steps were not separately committed, the deviation is noted in that task's commit message.

## Global Constraints
- V1: private single-user, Windows portable ZIP, later Android and iOS.
- UI: modern dark three-pane shell with smart views and nested task details.
- Every task can have its own note, deadline, priority and children; parent closure is manual after all children complete.
- Offline-first local SQLite and future Supabase sync; production writes require separate explicit owner approval.
- No commits containing secrets, service-role keys, connection strings, tokens or real personal tasks.
- Use feature branches, reviewable commits, exact-HEAD CI, owner-reviewed merges.
- Avoid overly broad dependency additions; pin SDK/plugin versions and commit lockfile.
- Keep default branch `main` deploy-free; documentation-only changes do not authorize implementation or production access.

## Review Focus
1. **No toolchain / missing Windows build support**: bootstrap instructions fail cleanly and name prerequisites; Task 1 checks clean runner prerequisites.
2. **Portable ZIP extracted into paths containing spaces / Unicode**: build smoke check runs from such a path; Task 4.
3. **Wrong or absent secret configuration**: app runs local demo without accessing Supabase; Task 2.
4. **Incorrect parent completion semantics**: a child's completion never closes its parent; Task 3.
5. **CI green on non-Windows but Windows binary broken**: Windows smoke build and artifact checks mandatory; Task 4.

---

## File Map
- `README.md`: user/developer entrypoint and support assumptions.
- `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.gitignore`: pinned Flutter project toolchain and quality baseline.
- `lib/main.dart`: minimal Flutter entrypoint.
- `lib/app/nexora_app.dart`: application root and theme shell.
- `lib/features/tasks/domain/task_status.dart`: pure domain status enumeration and transition rules.
- `lib/features/tasks/domain/task_completion.dart`: recursive completion projection based on leaf and child statuses.
- `test/app/nexora_app_test.dart`: boot test without network.
- `test/features/tasks/domain/task_completion_test.dart`: parent completion regression.
- `tool/package_windows.ps1`: portable build packaging and executable path tests.
- `.github/workflows/ci.yml`: analyzer, tests and Windows build gates.
- `docs/architecture/decisions/0001-flutter-offline-first.md`: reasoned architecture decision and boundaries.
- `docs/architecture/sync-contract.md`: future sync invariants, not a sync implementation.
- `docs/operations/supabase-access.md`: access verification and no-write gate.
- `docs/superpowers/plans/2026-11-11-nexora-phase-0-foundation.md`: this plan.

### Task 1: Reproducible Flutter Workspace

**Files:** Create `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.gitignore`, `README.md`, generated `windows/` and `lib/main.dart`. Test: `test/app/nexora_app_test.dart`.

**Interfaces:** Produces `main()` launching `NexoraApp`, and `NexoraApp extends StatelessWidget` in Task 2. No network dependencies.

- [ ] **Step 1: Verify SDK and host**. Run `flutter --version` and `flutter doctor -v` on Windows; record exact Flutter/Dart versions and Visual Studio C++ desktop workload requirements in README. Expected: Windows desktop toolchain available or explicit blocker.
- [ ] **Step 2: Scaffold smallest desktop app**. Run `flutter create --platforms=windows --project-name nexora .` on the implementation branch, with Flutter version pinned by team-supported mechanism. Expected: `windows/`, Flutter manifest, runnable `main.dart`.
- [ ] **Step 3: Write failing widget test** `test/app/nexora_app_test.dart`: pump `NexoraApp()`, expect `find.text('Nexora')` one widget, expect zero `FlutterError`. Run `flutter test test/app/nexora_app_test.dart`; expected FAIL until app root implemented in Task 2.
- [ ] **Step 4: Commit clean scaffold**. Commit generated project, manifest, lockfile, README prerequisites and failing test as `chore: bootstrap Windows Flutter workspace`; intentionally keep failure as declared dependency for Task 2.

### Task 2: Standalone App Shell with No Cloud Dependency

**Files:** Create `lib/app/nexora_app.dart`; modify `lib/main.dart`; test `test/app/nexora_app_test.dart`.

**Interfaces:** `class NexoraApp extends StatelessWidget` (const constructor) returns `MaterialApp` with `ThemeMode.dark` default, title `Nexora`. UI future integration route does not yet require authenticated state.

- [ ] **Step 1: Extend failing test**: assert text `Nexora` and `Offline ready` are visible on first render without configuration; verify no HTTP mocking or Supabase initialization.
- [ ] **Step 2: Confirm red**. Run `flutter test test/app/nexora_app_test.dart`; expected FAIL.
- [ ] **Step 3: Implement shell**. Add `NexoraApp`, set app title and dark theme, single diagnostic home widget and text placeholders. Keep secrets/config out of code.
- [ ] **Step 4: Confirm green and analyze**. Run `flutter test test/app/nexora_app_test.dart` then `flutter analyze`; expected PASS and no analyzer issues.
- [ ] **Step 5: Commit** `feat: establish offline-safe Nexora app shell`.

### Task 3: Parent Completion Domain Contract

**Files:** Create `lib/features/tasks/domain/task_status.dart`, `lib/features/tasks/domain/task_completion.dart`; test `test/features/tasks/domain/task_completion_test.dart`.

**Interfaces:** `enum TaskStatus { open, inProgress, review, done, archived }`. `TaskCompletion summarizeChildren(Iterable<TaskStatus> directChildren)` returns immutable `TaskCompletion({required int total, required int done, required bool eligibleForReview})`. `eligibleForReview` true only when `total > 0 && done == total`. This is a derived projection, not a persisted parent status transition.

- [ ] **Step 1: Write failing tests**: empty children -> (0,0,false); [done,done] -> (2,2,true); [done,inProgress] -> (2,1,false); [archived] -> (1,0,false); `eligibleForReview` never returns parent `done`.
- [ ] **Step 2: Run red**. `flutter test test/features/tasks/domain/task_completion_test.dart`; expected FAIL.
- [ ] **Step 3: Implement minimal pure Dart types and function** with the signatures above. Do not introduce database dependencies.
- [ ] **Step 4: Run green**. `flutter test test/features/tasks/domain/task_completion_test.dart` and `flutter analyze`; expected PASS.
- [ ] **Step 5: Commit** `test: lock manual parent-completion semantics`.

### Task 4: Windows Portability and CI Gate

**Files:** Create `tool/package_windows.ps1`, `.github/workflows/ci.yml`; modify `README.md`.

**Interfaces:** `tool/package_windows.ps1` accepts `-OutputDir <path>`, builds `flutter build windows --release`, copies *entire* Release bundle (exe, DLLs, data), writes `nexora-windows-portable.zip`. Test harness asserts extracted `nexora.exe` launches and exits cleanly via controlled close (no installer).

- [ ] **Step 1: Write smoke verification** in packaging script: ensure release exe, Flutter engine DLL and data directory exist; ensure packaging output is non-empty and executable relative paths intact.
- [ ] **Step 2: Run red**. Execute script before packaging implementation; expected fail on missing output or missing bundle.
- [ ] **Step 3: Implement packaging script** using Windows PowerShell supported by Windows CI; stage to temp directory with spaces and non-ASCII characters to test path handling; create ZIP from full Release directory, not only exe.
- [ ] **Step 4: Add GitHub Actions** on PR and push to main (Windows runner): Flutter stable pinned to chosen version, `flutter pub get`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, `flutter build windows --release`, `tool/package_windows.ps1`; upload ZIP artifact. Workflow must not use Supabase secrets.
- [ ] **Step 5: Verify green on exact commit HEAD**; Windows ZIP generated and manual smoke test passes on clean Windows machine. Record known limitations for native notifications and corporate restrictions.
- [ ] **Step 6: Commit** `ci: enforce Windows build and portable ZIP smoke gates`.

### Task 5: Architecture Decision and No-Write Supabase Gate

**Files:** Create `docs/architecture/decisions/0001-flutter-offline-first.md`, `docs/architecture/sync-contract.md`, `docs/operations/supabase-access.md`; update `README.md`.

**Interfaces:** Immutable docs contracts for later phases. Sync operation fields: `operation_id: UUID`, `workspace_id: UUID`, `entity_type: string`, `entity_id: UUID`, `base_revision: int`, `patch: JSON`, `created_at: UTC`. Server applies only once per operation and emits monotonic server-side sync cursor, tombstones retained until safe compaction.

- [ ] **Step 1: Write ADR checks**: document Flutter Windows/Android/iOS target; repository boundary; local write-first behavior; future Supabase server authority; no secret key in client.
- [ ] **Step 2: Document failure cases**: offline restart, duplicate operation replay, both devices edit same field, one device deletes a parent, client clock drift, expired token and out-of-order pagination. Define expected no-loss behavior and test owner for Phases 2/3.
- [ ] **Step 3: Document Supabase read-only prerequisite**: confirm project ID `uicccaawtjvqggeufbez` via authorized connector, confirm identity/org and project status, inspect existing schemas and RLS policies without writes, reject access to other projects as substitute; require explicit owner go-ahead for migrations/secrets/deploy. Verified on 2026-11-11 (read-only): project URL matches the target; migration list empty; `public` schema has zero tables and zero policies.
- [ ] **Step 4: Document access-check acceptance**: `PASS` only on read-only get_project + safe schema inspection for exact ID; `BLOCKED` if not listed or permission denied; zero mutations.
- [ ] **Step 5: Run doc/link and repository cleanliness check**; `git diff --check`, `flutter analyze`, `flutter test`, exact-HEAD CI PASS.
- [ ] **Step 6: Commit** `docs: define offline sync contract and Supabase authorization gate`.

## Phase 0 Acceptance / Handoff
- [ ] PR contains all expected project files; no secrets or credential material.
- [ ] GitHub CI green on final commit HEAD and Windows portable ZIP attached.
- [ ] Owner reviews UI placeholder and runnable ZIP; no production changes.
- [x] Supabase accessibility recorded as `PASS` (read-only verification, 2026-11-11). Re-verify before any hosted change.
- [ ] Document precise follow-on plan per phase before implementing it.

## Subsequent Plans (separate, reviewable phases)
1. **Phase 1 UI:** `2026-11-11-nexora-phase-1-desktop-ui.md` — smart views, project and recursive task tree, details editor and free notes; widget/golden/keyboard tests; demo-only data.
2. **Phase 2 Local Persistence:** `2026-11-11-nexora-phase-2-offline-domain.md` — SQLite migrations, repositories, recurring task invariant checks, durable autosave, local search, outbox; migration and crash-recovery tests.
3. **Phase 3 Cloud Sync:** `2026-11-11-nexora-phase-3-supabase-sync.md` — Supabase Auth, RLS with workspace isolation, server revision protocol, paginated pull, conflicts and deletions, contract/integration/negative tests; separate approval before hosted migrations.
4. **Phase 4 Windows Release:** `2026-11-11-nexora-phase-4-windows-rc.md` — reminder scheduling while running, tray integration, secure local session, export/restore, Windows portable acceptance; no auto-release.

## Out-of-Scope Release Sequence
Android APK and iOS app follow V1 and reuse the domain/persistence/sync contracts. Cross-device reminders, notification permissions and signing/distribution need independent mobile implementation plans.

## Proposed Execution
Use subagent-driven development where available for each Phase 0 task, independent review and exact-HEAD CI. Never merge/deploy automatically. After Phase 0 accepted, author and approve Phase 1 implementation plan before feature code.
