# Provenance of the v1 SQLite fixtures

| File | What it is | How it was produced |
|---|---|---|
| `v1_migration_statements.golden.txt` | The five statements of migration 1 joined with `\n-- next statement --\n` (Dart drops the first newline after `'''`) | `python3` extracted the string literals from `lib/features/tasks/data/migrations.dart` at the S2 baseline (`806760f`) |
| `v1_schema_fingerprint.golden.txt` | `type\|name\|tbl_name\|sql` for every `sqlite_master` row that has SQL, ordered by type then name | Python `sqlite3` (SQLite 3.53.1) applied to the frozen DDL in `synthetic_v1.sql`, independent of the Dart code |
| `synthetic_v1.sql` | Frozen copy of the v1 DDL plus invented rows: 2 projects, 3 tasks (parent/child, a tombstone, `done`/`archived`), 5 outbox rows covering `pending`, `sent`, `acked`, `failed` and base version 0 | Hand-written; every id, title and note is synthetic |
| SHA-256 constant in `migration_v1_golden_test.dart` | SHA-256 of the golden statement text | `hashlib.sha256` over the same text |

No file is derived from a real user database. No real user database was read or modified. The tests copy the fixture into a temporary file; the fixture itself is never opened in place.
When migration 2 (S5) is added, these goldens stay valid: they describe migration 1 only. If migration 1 itself must ever change, that is an owner decision and these files are regenerated deliberately with a new provenance entry.
