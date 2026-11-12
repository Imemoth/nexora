# Phase 2A — SAVE-PERSIST-01 Windows acceptance

**Status: OWNER PASS for the tested Windows build (artifact `13944534554`, commit `c970d611d7dc2d5a9ca4af5b2b33cc41d91441fa`), recorded 2026-11-12.**

The graphical acceptance was performed **manually by the owner**. The agent did not run it and does not claim to have run it. The owner supplied screenshots as evidence; the agent has not reproduced or independently reviewed them, and they are not stored in this repository. Only what the owner confirmed is recorded below. Anything not confirmed is marked "not recorded".

This acceptance applies to the build named above and to no other build. See section 6.

## 1. What is automated, and what is not

| Check | Where it runs | Result |
|---|---|---|
| SQLite repository, transactions, failed-write rollback, migrations, reopen, owner id, path resolution | `flutter test` (CI and local) | CI run 43219760973 on `c970d61`: success (see section 6) |
| Save, restart and Discard at the workspace level, against a real file | `flutter test`: `workspace_sqlite_test.dart` | CI run 43219760973: success |
| Cross-process restart: one process writes, a new process reads back | `tool/persistence/restart_check.ps1` (CI step after the tests) | Local: PASS. CI run 43219760973: success |
| Portable ZIP contains `sqlite3.dll`, and it matches the pinned SHA-256 | `tool/package_windows.ps1` (CI) | CI run 43219760973: success |
| Packaged app starts, opens a SQLite file in a temp folder, and closes with exit 0 | `tool/package_windows.ps1` smoke test (CI) | CI run 43219760973: success |
| **Real user flow on the packaged Windows app: create, edit, Save, close the process, relaunch, check the data** | **Manual (this checklist), performed by the owner** | **OWNER PASS on artifact `13944534554`, 2026-11-12 (see section 4)** |

The automated checks prove the storage layer and the packaged native library. They do not prove the graphical flow. Only the manual run does that.

## 2. Build to test

The owner tested the `nexora-windows-portable` artifact from CI run `43219760973` (artifact ID `13944534554`), built from commit `c970d611d7dc2d5a9ca4af5b2b33cc41d91441fa`.

Expected database location: `%LOCALAPPDATA%\Nexora\nexora.db`. The app creates it on first launch.

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

## 4. Evidence (owner-confirmed, 2026-11-12)

### Build identity (from CI, verified by the agent against the GitHub API)
| Field | Value |
|---|---|
| Commit | `c970d611d7dc2d5a9ca4af5b2b33cc41d91441fa` |
| CI run | `43219760973`, conclusion success |
| Artifact | `13944534554`, name `nexora-windows-portable`, 13,034,655 bytes |
| Artifact digest reported by GitHub | `sha256:67bfe113f31fc9cebb4d260613c6a07797662b67a55dd199feff41091d6a2f8c` (digest of the downloaded artifact archive as reported by the GitHub API; not a value the owner computed) |
| Artifact retention | expires 2026-11-26 |

### Owner-confirmed results
| Check | Result |
|---|---|
| Saved project and tasks survive an application restart | **PASS** |
| Saved subtasks and the task hierarchy persist | **PASS** |
| Task fields retain their saved values | **PASS** |
| `nexora.exe` terminates completely after the window is closed | **PASS** |
| Edit a task, switch to another task, choose **Discard**: the edit does not persist | **PASS** |
| Edit a task, close the application, choose **Discard**: the edit does not persist | **PASS** |
| **Failed Save** | **Not performed manually.** Covered by the automated fault-injection tests (for example "failed writes ... no partial row or outbox entry" and "a failed Save keeps the draft") |
| **Overall SAVE-PERSIST-01** | **PASS for the tested Windows build** |

### Not recorded
The owner did not supply, and this document does not state: time of day, Windows version and edition, extraction path, a checksum of the ZIP the owner computed locally, or a per-step log of procedure steps 2, 4 and 5. The database-file-present check is likewise not recorded.

## 5. Failure handling

- If a saved change is missing after a relaunch, record the exact steps, keep the database file, and do not overwrite it. Report it before any further run.
- If the app shows the startup error screen, the database could not be opened. Record the screen text and the file's presence. Do not delete the file.

## 6. Build identity: accepted build versus later builds

- **Manually accepted build:** commit `c970d611d7dc2d5a9ca4af5b2b33cc41d91441fa`, CI run `43219760973`, artifact `13944534554`. CI steps on that run all succeeded: dependency resolution, format, analyze, test, cross-process SQLite restart check, Windows release build, package and smoke-test of the portable ZIP, upload.
- **Later builds:** every later commit on this branch (the merge of `main` that brought in the shared documentation, and this record) is a different commit and produces a different CI run and a different artifact with its own checksum. **Manual acceptance is not transferred to a later artifact.** It stays attached to artifact `13944534554`.
- **Executable change between the accepted commit and later commits:** none. Against `c970d61`, the later commits add or change documentation files only (shared architecture documents from `main` and this record); no file under `lib/`, `test/`, `tool/`, `windows/`, `pubspec.yaml`, `pubspec.lock` or `.github/` differs. The PR description records the CI result of the final head separately. A repeat of manual acceptance is therefore not required by the source comparison, but whether to repeat it on the final artifact is the owner's decision.
