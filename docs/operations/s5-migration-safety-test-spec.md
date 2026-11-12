# S5 migration safety and backup test specification

Status: **specification (S5-0 partly implemented), reconciled 2026-11-12 with the Session B corrected specification** (`docs/coordination/phase-3-s5-outbox-v2.md`; tags [A]/[R]/[P] as defined there). Implemented now: the v1 freeze (golden statement hash, golden schema fingerprint, synthetic v1 fixture opens unchanged) and outbox/domain failure injection. Everything else below is implemented in S5 together with migration 2. SQLite schema v2 is **not** part of this slice. No test opens or modifies a real user database; all tests use synthetic files created in a temporary directory.

## 1. Fixtures and provenance
`test/fixtures/v1/` (see `PROVENANCE.md`): frozen v1 DDL with synthetic rows covering every v1 outbox state and a pending create (`base_version = 0`). Additional S5 fixtures must be synthetic, documented in `PROVENANCE.md`, and generated independently of the code under test.

## 2. Backup policy under test (design: S5 doc section 6, backup under lock)
Before migration 2 runs on an existing file the app writes a backup next to it (`<name>.v1.bak`, created with SQLite `VACUUM INTO` or the online backup API so WAL content is included, never by copying a live WAL database file alone). The backup is verified by opening it read-only and comparing `user_version = 1` and the row counts, before the migration starts; if the backup fails, the migration does not run and the app reports the error. **The app never deletes, rotates, prunes or overwrites a backup automatically** (owner direction 2026-11-12). Retention is an owner-controlled decision (O-10, open); until it is decided a backup stays on disk until a person removes it. The order of outbox rows is never taken from a backup: it is read from the original file inside the migration transaction (rowid, see M2). The backup-under-lock procedure from the corrected Session B report is **not yet incorporated** (the report has not been received; blocker B-16).

## 3. Test matrix
| ID | Test | Status |
|---|---|---|
| M0a | v1 statement text and SHA-256 are unchanged | **done** (S5-0) |
| M0b | Fresh file gets exactly the golden v1 schema; frozen fixture schema equals it | **done** (S5-0) |
| M0c | A v1 file with synthetic data opens at v1 with all rows, versions and outbox rows unchanged | **done** (S5-0) |
| F0 | A failing outbox insert rolls the domain write back; a failing domain write leaves no outbox row; edit and delete variants; the repository works after the failure is removed | **done** (S5-0) |
| M1 | Migration v1 to v2 preserves every row of `projects`, `tasks`, `meta` (per-row checksums) and every outbox row's `operation_id`, `entity_*`, `payload_json`, `base_version`, `created_at_utc`, `attempts`, `last_error` | S5 |
| M2 | Outbox order: `seq` follows the verified v1 **`rowid`** order for all fixture rows, **not** `created_at_utc`. The fixture must contain rows whose `created_at_utc` order differs from their `rowid` order (a clock that went backwards), so the test fails if the migration sorts by time. `seq` values are monotone after new inserts and after restart | S5 |
| M3 | State handling (see also M15, M16): `pending` stays `pending`; `acked` becomes `applied` (its local `version` untouched); **`sent` and `failed` are preserved** (owner direction C3): after migration every such row still exists with its original `operation_id`, `entity_*`, `payload_json`, `base_version`, `attempts`, `last_error` and original meaning, and none is `in_flight`, resent or re-based | S5 (representation blocked on S5-Q1) |
| M13 | No automatic replay: after migration and after any number of restarts with no network, no outbox row changes state or `attempts`, and the sync transport receives no call; no local `version` of any row changes | S5 |
| M14 | No automatic backup deletion: a test that creates several backups, runs migration and restarts repeatedly, and asserts every backup file still exists unchanged; the code has no deletion path for backups | S5 |
| M15 | Classification: a fixture with only pending base-0 upserts migrates as class S (version 0, first create live, later upserts archived `folded_into_create`); every entity with `sent`, `failed`, `acked`, a delete, a base > 0, a non-S parent, or a folded payload that differs from the row is class U (no create op, `sync_scope = 'unclassified'`, version kept verbatim, operations archived verbatim); children of U are U; demo-like rows are U. A hostile sample: an `acked` row whose version is 5 keeps version 5 | S5 [P] |
| M16 | Abort cases leave the file untouched with the exact code: unknown `user_version`, failed integrity check, binding mismatch, a 300-character title (never truncated), FK violation, digest mismatch, row-count mismatch | S5 [P] |
| M17 | Backup under lock: the backup digest (including rowid order) equals the digest computed inside `BEGIN IMMEDIATE`; a concurrent writer gets `database is locked`; the backup is still v1 after migration; a failed verification renames the partial to `.failed`; an existing backup is never overwritten | S5 [P] |
| M18 | Pre-commit vs post-commit: an error or crash before `COMMIT` leaves v1 and reruns; after `COMMIT` only `foreign_keys = ON`, the migration report (retried) and `in_flight` requeue follow; a post-commit invariant failure pauses sync and offers only an owner-authorized restore | S5 [P] |
| M19 | v2 invariants listed in S5 doc section 8, including the items reported as not yet exercised: `AUTOINCREMENT` non-reuse of `seq`, conflict-evidence immutability trigger, composite FK across projects, transmitted non-create base >= 1 CHECK | S5 [P] |
| M20 | Re-run of the whole matrix on the pinned Dart `sqlite3` 3.9.1 bundle (the report's checks ran on Python SQLite 3.50.4 and are not reproduced here) | S5 gate (B-17) |
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
3. The migration never runs on an unverified backup, and never deletes any backup.
4. No test and no CI step touches a database outside its temporary directory.
