# Phase 2A — SAVE-PERSIST-01 Windows acceptance

**Status: PENDING (owner manual run).** The agent did not perform the graphical acceptance. Nothing in this document claims that it passed. Fill in the evidence table in section 4 when it is run.

## 1. What is automated, and what is not

| Check | Where it runs | Result |
|---|---|---|
| SQLite repository, transactions, failed-write rollback, migrations, reopen, owner id, path resolution | `flutter test` (CI and local) | See the CI run for the final head |
| Save, restart and Discard at the workspace level, against a real file | `flutter test`: `workspace_sqlite_test.dart` | See the CI run |
| Cross-process restart: one process writes, a new process reads back | `tool/persistence/restart_check.ps1` (CI step after the tests) | Local: PASS. CI: see the CI run |
| Portable ZIP contains `sqlite3.dll`, and it matches the pinned SHA-256 | `tool/package_windows.ps1` (CI) | See the CI run |
| Packaged app starts, opens a SQLite file in a temp folder, and closes with exit 0 | `tool/package_windows.ps1` smoke test (CI) | See the CI run |
| **Real user flow on the packaged Windows app: create, edit, Save, close the process, relaunch, check the data** | **Manual (this checklist)** | **PENDING** |

The automated checks prove the storage layer and the packaged native library. They do not prove the graphical flow. Only the manual run does that.

## 2. Build to test

Use the portable ZIP from the CI run for the final commit of the Phase 2A pull request (the `nexora-windows-portable` artifact). Record the run ID and the SHA-256 of the ZIP you test.

Expected database location: `%LOCALAPPDATA%\Nexora\nexora.db`. The app creates it on first launch. Do not delete it between runs.

## 3. Manual procedure (SAVE-PERSIST-01)

Use a folder path with a space and a non-ASCII character to extract the ZIP.

1. Launch `nexora.exe`. Confirm the window opens and the workspace is empty, or shows the default "Inbox" project if this is the first launch on this machine.
2. Create a project (or use "Inbox") and a task. Give it a title.
3. Create a subtask under that task.
4. Edit the task: title, status, priority, due date and notes. Edit the subtask's title.
5. Click **Save**. Confirm the "Edited, not saved" indicator disappears.
6. Close the whole application: use the window close button, and confirm in Task Manager that no `nexora.exe` process is left.
7. Relaunch the same `nexora.exe`.
8. Confirm the project, the task and the subtask are still there, with the same hierarchy, and that every field you changed in step 4 has its saved value.
9. **Discard:** edit a task, click another task, choose **Discard**. Confirm the discarded edit is not there after a restart (close and relaunch).
10. **Unsaved exit:** edit a task, close the window, choose **Discard** in the dialog. Relaunch. Confirm the edit is not there.
11. **Failed Save:** there is no safe UI-only way to force a save failure. Its behaviour is covered by the automated test "a failed Save keeps the draft". Record this item as "not run" unless you have a fault-injection method you trust.

Record a pass or fail for each step, with the time and a short note.

## 4. Evidence (owner fills in)

| Field | Value |
|---|---|
| Date / time | |
| Windows version and edition | |
| CI run ID for the final commit | |
| ZIP SHA-256 (tested) | |
| Extraction path used | |
| Database file present at `%LOCALAPPDATA%\Nexora\nexora.db` after first launch | |
| Step 2: project and task created | |
| Step 4: edits made (title, status, priority, due date, notes, subtask) | |
| Step 5: Save clicked, indicator cleared | |
| Step 6: process fully gone after close | |
| Step 8: all data intact after relaunch | |
| Step 9: Discard not persisted | |
| Step 10: unsaved exit, Discard not persisted | |
| Step 11: failed Save | Not run / result |
| Overall SAVE-PERSIST-01 result | PENDING |

## 5. Failure handling

- If a saved change is missing after a relaunch, record the exact steps, keep the database file, and do not overwrite it. Report it before any further run.
- If the app shows the startup error screen, the database could not be opened. Record the screen text and the file's presence. Do not delete the file.
