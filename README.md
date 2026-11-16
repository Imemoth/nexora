# Nexora

Private, offline-first task and notes app. V1 targets a portable Windows ZIP. Android and iOS follow later. See `docs/superpowers/specs/2026-11-11-nexora-v1-design.md`.

## Toolchain (pinned)
- Flutter **3.47.9** (stable), Dart **3.13.7**. Pinned in CI (`FLUTTER_VERSION` in `.github/workflows/ci.yml`) and recorded in `.metadata`.
- Third-party GitHub Actions are pinned to commit SHAs.
- The owner's machine does not need the Flutter SDK. CI builds and tests the app.

## Windows support
- **Minimum:** Windows 10 (64-bit, x64). Flutter 3.47 lists Windows 10 and 11 as supported and tests Windows 10 in CI. Windows 8 and earlier are unsupported.
- **Local builds (optional):** Visual Studio with the "Desktop development with C++" workload, and Flutter 3.47.9.
- **Known limitations:** reminders are stored on this device only (not synchronized), and notifications stop when the app has fully exited (minimize to the tray to keep them). Corporate policies may block unsigned executables or extraction paths. Test on a clean machine before release.

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

**Which build is this?** Account menu, *About Nexora*: version, source commit and build type (a DEVELOPMENT TEST build is marked). The same identity is in `BUILD-INFO.json` inside the ZIP. The version has one source, the `version:` line of `pubspec.yaml`; how to raise it and how to trace an artifact to its source: [`docs/operations/versioning-and-build-identity.md`](docs/operations/versioning-and-build-identity.md).

## Current status
Project status, migrations, decisions, gates and blockers live in one place: [`docs/coordination/status-register.md`](docs/coordination/status-register.md) (documentation map: [`docs/README.md`](docs/README.md)). In short: the Windows app saves tasks and projects in local SQLite (schema v3) and works fully offline. **Phase 3 (account sign-in, import of local data, automatic bidirectional synchronization, offline recovery, conflict detection and interactive conflict resolution) is implemented and accepted for the current TEST environment** (hosted Supabase TEST project, test accounts only). The default build keeps synchronization **off** (`NEXORA_SYNC` build flag); a separate sync-enabled DEVELOPMENT TEST build (workflow `windows-sync-dev-build.yml`) connects to the TEST project. There are no production users and no production hardening yet. **Phase 4 (device-local task reminders, Windows notifications, system tray, single instance) is implemented and accepted for the TEST environment** and awaits merge approval. Next development target: Phase 5 (UI/UX modernization). User guide: [`docs/operations/release-candidate-guide.md`](docs/operations/release-candidate-guide.md).

## Phase 1 UI (original in-memory prototype description)
Phase 1 built the Windows desktop UI over deterministic in-memory demo data; since Phase 2A the same UI persists to local SQLite.

What it does: a three-pane layout (sidebar, task tree, details editor), smart views (Today, Next 7 Days, Overdue, All), projects, search, sort, task and subtask creation, editing with Save and Revert, and an unsaved-change gate that protects edits on every navigation and on exit. Between 900 and 1099 px the details editor becomes an overlay. Below 900 px a desktop-only notice is shown.

Keyboard (Ctrl is the command key): Up and Down move through tasks; Right and Left expand or collapse; Enter focuses the title; Ctrl+F searches; Ctrl+N creates a task; Ctrl+Shift+N creates a subtask; Ctrl+S saves; Esc clears a non-empty search first, then returns focus to the list, and in the list clears the selection.

Acceptance: see [`docs/operations/phase-1-acceptance.md`](docs/operations/phase-1-acceptance.md) for CI evidence, artifact checksums and the manual Live Acceptance checklist. Phase 1 was accepted by the owner (see the register).

## Configuration and secrets
The default build runs with no configuration and makes no network calls (synchronization is off). The sync-enabled DEVELOPMENT TEST build is compiled with `--dart-define=NEXORA_SYNC=true` plus the project URL and the **public** anon (publishable) key of the TEST project, both public by design; the user signs in with an account on that project and the session is stored protected by Windows DPAPI. Never commit `.env` files, service-role keys, connection strings, passwords or tokens. Supabase access is documented in `docs/operations/supabase-access.md`.
