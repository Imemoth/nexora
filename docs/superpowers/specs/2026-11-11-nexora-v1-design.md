# Nexora V1 — Approved Product & Architecture Specification

**Approved:** 2026-11-11
**Status:** approved product direction; concrete dependencies remain implementation decisions
**Target:** personal-use offline-first task and notes application, team sharing later.

## Goals
- Flutter desktop application portable on Windows as extracted ZIP containing executable and runtime files; no installer required.
- Later Android and iOS apps using shared domain and sync contracts.
- Three-pane modern dark UI: smart-view/project sidebar, selected hierarchy/list, task details including nested subtasks and free-form notes. Light theme optional.
- Smart views: Today, Next 7 Days, Overdue, All; project filtering, searching, sorting.
- Arbitrarily nested tasks with their own title, status, due date, priority, formatted notes and reminders.
- Children have independent completion; all children complete yields parent "review" not automatically "done"; explicit parent closure required; leaf tasks closed manually.
- Windows reminders while app is running; tray minimizing; notification fallback when portable toast integration unavailable.
- Local-first editing, autosave, durable operation queue, resumable and idempotent sync, detection of same-field and note conflicts, no silent data loss.
- V1 single-person workspace, data model prepared for future sharing: workspace ownership, membership, resource IDs and authorization.
- Supabase Auth + Postgres/RLS; local SQLite; export/import with backup verification.

## Non-goals V1
- Multi-user collaboration, invitations, delegation, role editing and cross-user realtime presence.
- Android/iOS release, file attachments, complex analytics, cloud-initiated notifications, billing.
- Background reminders when the Windows application is not running.

## Data / security constraints
- Namespaced records with workspace_id. Future membership role table must not grant sharing during V1.
- App uses publishable key only and authenticated user JWT with least-privilege RLS. No service_role in client.
- Device-private token storage and protected local store; document portable-data encryption and logout policy.
- Task tree must reject self-parenting, cross-workspace parents and cycles; deterministic display order.
- Server timestamps in UTC; display in device timezone; distinguish date-only deadlines vs timestamp deadlines.
- Stable UUID IDs; version/revision plus tombstones for deletes and durable cursor-based pull.
- No silent last-write-wins for concurrent same-field changes; user-resolvable conflict records.
- No production writes, migration deployment or credential updates without specific owner authorization.

## Architecture
Flutter feature modules for navigation, tasks, notes, reminders, sync and account. SQLite is the interactive source of truth for UI. Domain/application logic separated from Flutter widgets and Supabase client. A repository/outbox sync boundary handles offline mutations and server version checks. Supabase Postgres + Auth + RLS is the cross-device authority.

## Candidate data model
workspaces(id, owner_user_id, name, created_at), workspace_members(workspace_id,user_id,role), projects(id, workspace_id,title,position,deleted_at, revision), tasks(id,workspace_id,project_id,parent_id,title,status,priority,due_at,due_date,position,completed_at,deleted_at,revision), task_notes(id,workspace_id,task_id,format,body,revision,deleted_at), reminders(id,workspace_id,task_id,notify_at,done_at), task_events(id,workspace_id,task_id,event_type,created_at), sync_changes(change_id,workspace_id,entity_type,entity_id,revision,changed_at,deleted_at). Final table and policy details must be decided in Phase 2/3 plans before implementation. local-only pending_operations, sync_cursor, conflicts, auth_device_state.

## Release gates
- Builds and launches from extracted Windows ZIP without installer.
- Local CRUD and notes survive restart fully offline; no lost outbox operations across restart.
- Two-device upload/download and idempotent retries verified.
- Conflicts between simultaneous offline edits preserve both versions and block unreviewed overwrite.
- RLS negative tests establish strict workspace isolation and forbid spoofed membership.
- Backup export/import and rollback restoration verified.
- Reminders display only during runtime and do not duplicate after snooze/ack.
- All mandatory CI tests and exact-HEAD manual acceptance pass before owner merge/release.

## Open constraints / external dependencies
- Supabase project `uicccaawtjvqggeufbez` is not accessible with current connector permissions (as of 2026-11-11); access must be resolved and verified read-only before any hosted migration.
- Confirm Windows minimum support/version based on Flutter stable and native integrations during Phase 0.
- Lock exact Flutter/Dart, SQLite, routing, state-management and editor package versions after toolchain verification; no broad unpinned dependencies.
- Company-sensitive content must be subject to organizational data security policy before using external cloud.
