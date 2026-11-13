# Nexora V1 release candidate: install, first run, sign-in, backup and recovery

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
1. Choose **Import local data** (empty-account card or the bar at the top).
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
