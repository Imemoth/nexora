# Nexora

Private, offline-first task and notes app. V1 targets a portable Windows ZIP. Android and iOS follow later. See `docs/superpowers/specs/2026-11-11-nexora-v1-design.md`.

## Toolchain (pinned)
- Flutter **3.47.9** (stable), Dart **3.13.7**. Pinned in CI (`FLUTTER_VERSION` in `.github/workflows/ci.yml`) and recorded in `.metadata`.
- Third-party GitHub Actions are pinned to commit SHAs.
- The owner's machine does not need the Flutter SDK. CI builds and tests the app.

## Windows support
- **Minimum:** Windows 10 (64-bit, x64). Flutter 3.47 lists Windows 10 and 11 as supported and tests Windows 10 in CI. Windows 8 and earlier are unsupported.
- **Local builds (optional):** Visual Studio with the "Desktop development with C++" workload, and Flutter 3.47.9.
- **Known limitations (Phase 0):** no notifications, tray, or reminders yet (Phase 4). Corporate policies may block unsigned executables or extraction paths. Test on a clean machine before release.

## Development
```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build windows --release
```

## Portable ZIP
`tool/package_windows.ps1` packages the full Release bundle (`nexora.exe`, Flutter engine DLLs, and `data/`). Extract the ZIP anywhere and run `nexora.exe`. No installer is needed.

## Current status
Project status, migrations, decisions, gates and blockers live in one place: [`docs/coordination/status-register.md`](docs/coordination/status-register.md) (documentation map: [`docs/README.md`](docs/README.md)). In short: the Windows app saves tasks and projects locally in SQLite (Phase 2A, merged); the Supabase schema foundation is applied to the hosted project; synchronization and sign-in are **not** active and the app makes no network calls.

## Phase 1 UI (original in-memory prototype description)
Phase 1 built the Windows desktop UI over deterministic in-memory demo data; since Phase 2A the same UI persists to local SQLite.

What it does: a three-pane layout (sidebar, task tree, details editor), smart views (Today, Next 7 Days, Overdue, All), projects, search, sort, task and subtask creation, editing with Save and Revert, and an unsaved-change gate that protects edits on every navigation and on exit. Between 900 and 1099 px the details editor becomes an overlay. Below 900 px a desktop-only notice is shown.

Keyboard (Ctrl is the command key): Up and Down move through tasks; Right and Left expand or collapse; Enter focuses the title; Ctrl+F searches; Ctrl+N creates a task; Ctrl+Shift+N creates a subtask; Ctrl+S saves; Esc clears a non-empty search first, then returns focus to the list, and in the list clears the selection.

Acceptance: see [`docs/operations/phase-1-acceptance.md`](docs/operations/phase-1-acceptance.md) for CI evidence, artifact checksums and the manual Live Acceptance checklist. Phase 1 was accepted by the owner (see the register).

## Configuration and secrets
The app does not connect to Supabase and runs with no configuration (synchronization is disabled). Never commit `.env` files, service-role keys, connection strings, or tokens. Supabase access is documented in `docs/operations/supabase-access.md`.
