# S5 migration safety and backup test specification

Status: **specification only (S5-0).** Implemented now: the v1 freeze (golden statement hash, golden schema fingerprint, synthetic v1 fixture opens unchanged) and outbox/domain failure injection. Everything else below is implemented in S5 together with migration 2. SQLite schema v2 is **not** part of this slice. No test opens or modifies a real user database; all tests use synthetic files created in a temporary directory.

## 1. Fixtures and provenance
`test/fixtures/v1/` (see `PROVENANCE.md`): frozen v1 DDL with synthetic rows covering every v1 outbox state and a pending create (`base_version = 0`). Additional S5 fixtures must be synthetic, documented in `PROVENANCE.md`, and generated independently of the code under test.

## 2. Backup policy under test
Before migration 2 runs on an existing file the app writes a backup next to it (`<name>.v1.bak`, created with SQLite `VACUUM INTO` or the online backup API so WAL content is included, never by copying a live WAL database file alone). The backup is verified by opening it read-only and comparing `user_version = 1` and the row counts, before the migration starts; if the backup fails, the migration does not run and the app reports the error. Retention (how long backups stay) is an owner decision; tests use the default "keep until the next successful start on v2 and then keep one".

## 3. Test matrix
| ID | Test | Status |
|---|---|---|
| M0a | v1 statement text and SHA-256 are unchanged | **done** (S5-0) |
| M0b | Fresh file gets exactly the golden v1 schema; frozen fixture schema equals it | **done** (S5-0) |
| M0c | A v1 file with synthetic data opens at v1 with all rows, versions and outbox rows unchanged | **done** (S5-0) |
| F0 | A failing outbox insert rolls the domain write back; a failing domain write leaves no outbox row; edit and delete variants; the repository works after the failure is removed | **done** (S5-0) |
| M1 | Migration v1 to v2 preserves every row of `projects`, `tasks`, `meta` (per-row checksums) and every outbox row's `operation_id`, `entity_*`, `payload_json`, `base_version`, `created_at_utc`, `attempts`, `last_error` | S5 |
| M2 | Outbox order: `seq` follows the v1 `created_at_utc, rowid` order for all fixture rows; `seq` values are monotone after new inserts and after restart | S5 |
| M3 | State mapping: `pending` stays, `sent` becomes `pending`, `acked` becomes `applied`, `failed` follows the decision S5-Q1 (the CR proposal's unchanged `failed` violates the v2 CHECK) | S5 (blocked on S5-Q1) |
| M4 | Failure injection at every statement of migration 2 (a trigger or a deliberately broken statement at each position): the file stays at `user_version = 1`, schema fingerprint equals the golden v1, rows unchanged | S5 |
| M5 | Crash mid-migration (process killed or connection closed before COMMIT, simulated by closing the handle inside the migration transaction): reopen gives v1 intact and the migration runs again successfully | S5 |
| M6 | Backup is created before migration, verified, and restorable: restoring the backup gives a file equal to the pre-migration fingerprint and rows | S5 |
| M7 | Backup failure (read-only directory) aborts the migration and leaves v1 untouched | S5 |
| M8 | A second open of a migrated file is a no-op (idempotent); a file with `user_version` greater than supported is refused and unchanged (exists for v1; re-asserted for v2) | S5 |
| M9 | After migration the golden **v2** schema fingerprint matches; the v1 goldens remain valid for migration 1 | S5 |
| M10 | Foreign keys and CHECK constraints are enforced after migration (`PRAGMA foreign_key_check` empty, `PRAGMA integrity_check` ok) | S5 |
| M11 | A pending create and its follow-up edits keep `base_version = 0` after migration | S5 |
| M12 | Disk-full and power-loss behavior | not testable in CI; documented risk, mitigated by single-transaction migration plus `synchronous = FULL` |

## 4. Rules for the implementation of S5
1. Each migration runs in one transaction together with `PRAGMA user_version` (already the v1 mechanism).
2. Table rebuild order: create new, copy, verify counts inside the transaction (abort on mismatch), drop old, rename.
3. The migration never runs on an unverified backup.
4. No test and no CI step touches a database outside its temporary directory.
