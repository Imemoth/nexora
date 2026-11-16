# Nexora V1 release candidate: install, first run, sign-in, backup and recovery

> **Policy:** Nexora is DEVELOPMENT/TEST only; no production exists; the Supabase project is DEV/TEST with mock data. Production-style rollback, release and compatibility parts below are optional guidance, not requirements; hosted writes still need the owner's separate authorization. See [`docs/development-environment-policy.md`](../development-environment-policy.md).

Audience: the owner installing the Windows release candidate (RC). Synchronization is **off by default**; the default build never contacts a server.

## 1. The RC package
Built by the `CI` workflow (job "Windows analyze, test, build, package") on the exact commit. The artifact `nexora-windows-portable` holds `nexora-windows-portable.zip` (the full Windows Release folder, smoke-tested by `tool/package_windows.ps1`) and `SHA256SUMS.txt` (SHA-256 of the ZIP, the commit, and every file in the ZIP).
Verify before use (PowerShell):
```powershell
(Get-FileHash -Algorithm SHA256 .\nexora-windows-portable.zip).Hash.ToLower()
```
It must equal the first line of `SHA256SUMS.txt`. Reproducibility: the build is pinned (Flutter 3.47.9, Dart 3.13.7, locked dependencies); the per-file hashes in `SHA256SUMS.txt` are what to compare between two builds of the same commit, because a ZIP container embeds timestamps and may differ byte for byte. The ZIP is not code-signed; Windows SmartScreen may warn on first run (blocker B-SIGN, accepted for a personal-use pilot).

## 2. Install
1. Extract the ZIP to a folder you own, for example `C:\Users\<you>\Apps\Nexora`. Keep the whole folder together (the executable needs the DLLs and `data` folder next to it).
2. Run `nexora.exe`. No installer and no administrator rights are needed. Delete the folder to uninstall; your data is stored elsewhere (section 3) and is not removed.

## 3. First run and where data lives
The local workspace is a SQLite file `%LOCALAPPDATA%\Nexora\nexora.db` (override with the `NEXORA_DB_PATH` environment variable). On first run a default project is created in this local workspace and nothing leaves the computer. If you used an earlier version, the file is upgraded in place **from a verified copy** `nexora.db.pre-v2-…bak` kept next to it; the upgrade stops and leaves the original untouched if the copy cannot be verified.
Other folders under `%LOCALAPPDATA%\Nexora`: `accounts\<account id>\nexora.db` (one database per signed-in account; created only when a synchronization build signs in) and `session\session.dpapi` (the refresh token, protected with Windows DPAPI for your Windows user; it is not readable as plain text and does not move to another user or computer).

## 4. Signing in (synchronization build only)
The default RC never shows account controls. A synchronization build is made with `--dart-define=NEXORA_SYNC=true` plus the project URL and the publishable (anon) key (`NEXORA_SUPABASE_URL`, `NEXORA_SUPABASE_ANON_KEY`); **never** a service-role key. It is not part of this RC's default package and is enabled only after the hosted acceptance operation and a separate owner authorization (`combined-hosted-acceptance-operation.md`, section 7).
Account setup, when authorized: the owner creates the account in the Supabase dashboard (public sign-up is to be off), confirms the email address, and sets a password of at least 12 characters. In the app choose **Sign in**, enter email and password. A signed-out app shows "local only". An account starts **empty**: nothing is created or imported automatically. The window then offers **New project** and **Import local data**.

## 5. Importing your local projects into the account (manual, preview first)
1. Choose **Import local data** (empty-account card, or the account menu at the bottom of the sidebar).
2. The preview lists the local projects that can be imported with their task counts and warnings: "Already imported into this account" (blocked unless you tick *Import again anyway*) and "A project with this name already exists". It also states how many records are **not offered** (local-only demo records, records of unknown origin, deleted records).
3. Tick the projects, choose for each a destination (**New project** or an existing project to merge into; tasks that duplicate an existing task under the same parent are skipped) and press **Import selected**.
4. Before anything is written the app makes a verified copy of the account database (`nexora.db.pre-import-<timestamp>.bak`, compared by content digest). The import is one all-or-nothing transaction. If anything fails, nothing is changed and the backup stays. The local workspace file is only read, never modified.
5. Imported records get new identifiers (the old-to-new mapping is stored in the account database) and are queued like any new record; they are sent by the normal synchronization. Pending work, task hierarchy and notes are preserved.

## 6. Backup and recovery
* **Backups the app makes:** `nexora.db.pre-v2-*.bak` (format upgrade) and `nexora.db.pre-import-*.bak` (before each import). They are never deleted automatically; you decide when to remove them.
* **Your own backup:** close Nexora and copy `%LOCALAPPDATA%\Nexora` (it contains the local database, the account databases and, for completeness, the protected session file). Copying while the app runs may capture a half-written file, so close it first.
* **Restore:** close Nexora, rename the current `nexora.db` (or `accounts\<id>\nexora.db`) to `…bad`, copy a `.bak` over to the original name, start the app. Pending synchronization work is part of the database and is restored with it.
* **Lost or revoked session:** the app shows "sign in again" and keeps every local change; sign in again and synchronization resumes. After a restore of an older database the server remains the authority for acknowledged data; unsent local changes that are older than the server state become visible conflicts, never silent overwrites.
* **Problem opening the database:** the app shows an error screen instead of overwriting anything.

## 7. Turning synchronization off
Run the default build (no `NEXORA_SYNC`). The account databases stay on disk with their pending work; nothing is sent. Server-side kill switches are in `combined-hosted-acceptance-operation.md`, section 6.

## 9. The Phase 5 window (Midnight)
Phase 5 changes how Nexora looks and adds a few controls; your data and the sync behaviour are unchanged.
- **Layout:** sidebar (Views: Dashboard, Today, Next 7 Days, Overdue, All; Projects with **+** for a new project), the task list in the centre, the task editor on the right (an overlay between 900 and 1099 px wide; below 900 px the list stays usable and a notice explains the minimum width).
- **Account menu:** the row at the bottom of the sidebar ("Local workspace" or "Signed in as ...") opens a menu: **Theme** (System, Light, Dark; saved on this device, not in your account), **Import local data** and **Sign out** (signed-in builds only), **Keyboard shortcuts**. Signing out with unsaved edits asks first (Save, Discard, Cancel).
- **Sync card:** the card above the account row tells the state in words (Up to date, Synchronizing, N changes waiting, Offline, N changes refused, N conflicts, Sign in needed, Device removed, Sync stopped, Local only) with its one action. Only conflicts, sign-in needed, device removed and sync stopped also show a bar across the top of the window; it goes away by itself when the problem is gone. The default build only ever shows "Local only".
- **Task list:** status chips (All, Open, In progress, Review, Done) with counts, search, sort, and **quick add** (type a title and press Enter) at the top of the list. Dates read Today, Tomorrow, Mon 16 Nov, Overdue - Thu 12 Nov.
- **Editor:** Save and Revert stay pinned at the top and show "Saved" or "Edited, not saved". The reminder block below the task is saved immediately, on this device only, and is not part of Save or Revert. **Delete task** (and **Delete project** from the selected project's menu) asks first, says how many subtasks or tasks go too, and cannot be undone; the last project cannot be deleted.
- **Dashboard:** counts for Today, Overdue, Next 7 Days and All, the reminders on this device (with Dismiss all), what needs attention, the current sync state and project progress.

## 12. Version 1.1.0+2: the sign-in and synchronization test build
- **Two builds, one version.** `nexora-windows-portable.zip` is local only (About: Synchronization Off). `nexora-windows-sync-DEVELOPMENT-TEST.zip` (workflow `windows-sync-dev-build`) offers Sign in and synchronization against the TEST project; About shows **DEVELOPMENT TEST** and Synchronization **On**. Both carry `BUILD-INFO.json`; see `versioning-and-build-identity.md`.
- **Upgrading from 1.0.0+1 (local only).** Opening the local file with 1.1.0+2 migrates it in place (schema 5 to 6; due times are kept). **A 1.0.0+1 build cannot open it afterwards.** Before the first start of the new version, copy `%LOCALAPPDATA%\Nexora\nexora.db` (and `nexora.db-wal` if present) to a safe place.
- **Local and account workspaces stay separate.** Signing in never uploads local tasks. Use *Import local data* (account menu): the preview lists projects and, while the server cannot store due times, says plainly that times are imported as dates only.
- **Due times and the server.** The time row is available in the local workspace. While signed in it works only after the TEST server was migrated (`docs/operations/due-time-hosted-migration.md`, owner approval needed); until then the time row is disabled with the reason, and dates sync as before.
- **Tree.** A parent shows its direct children by default; deeper levels open on request. Clicking a related subtask in the details panel opens the path to it.

